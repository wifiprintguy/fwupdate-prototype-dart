import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:ipp/ipp.dart';

import 'client_event_log_entry.dart';
import 'simulated_identity.dart';

/// A live conversation with one Printer-app instance: connect, inspect its
/// attributes, ask it to check for/install Firmware, and poll for progress.
///
/// This is the "system under test" harness side of the project — it's a
/// deliberately well-behaved reference Client, built to demonstrate the
/// conformance checklist from the README (e.g. §"Treats a mid-update
/// connection failure as transient"): [_pollTick] keeps polling through
/// transport errors instead of surfacing them as fatal, exactly because a
/// real Printer can go dark mid-reboot per FWUPDATE §4.4/§5.2's note.
class PrinterSession extends ChangeNotifier {
  PrinterSession({
    required this.printerUri,
    required this.identity,
    String? displayName,
    this.pollInterval = const Duration(seconds: 2),
    this.statusMonitorInterval = const Duration(seconds: 5),
    this.autoCheckStaleThreshold = const Duration(hours: 1),
  }) : displayName = displayName ?? printerUri.host;

  final Uri printerUri;
  final String displayName;
  final SimulatedIdentity identity;

  /// How often to re-fetch attributes while a check/update is outstanding.
  /// Overridable so tests don't have to wait out a production-grade
  /// cadence to observe a fast simulated pipeline complete.
  final Duration pollInterval;

  /// How often to refresh attributes for as long as this printer is open —
  /// unconditional, not something the tester toggles on/off: a "normal"
  /// Client UI just doesn't show stale status while you're looking at it.
  /// The cadence itself is tunable from the Settings tab, hence mutable.
  Duration statusMonitorInterval;

  /// How stale `printer-new-firmware-check-date-time` has to be before this
  /// Client decides to proactively send Check-For-New-Printer-Firmware on
  /// its own, mirroring how a well-behaved real Client would periodically
  /// re-check rather than either spamming the operation or never running
  /// it unless a human clicks a button. Tunable from the Settings tab.
  Duration autoCheckStaleThreshold;

  void setStatusMonitorInterval(Duration interval) {
    statusMonitorInterval = interval;
    _startStatusMonitor();
    _notify();
  }

  void setAutoCheckStaleThreshold(Duration threshold) {
    autoCheckStaleThreshold = threshold;
    _notify();
  }

  final IppClientTransport _transport = IppClientTransport();
  int _nextRequestId = 1;

  IppMessage? _lastResponse;
  bool isConnected = false;
  bool isBusy = false;
  String? lastError;

  /// True from the moment this session sends Check-For-New-Printer-Firmware
  /// — including the Client's own automatic background checks (see
  /// [_maybeAutoCheck]), which nobody clicked a button for — until polling
  /// for its result settles. Lets the UI show "checking" instead of
  /// `printer-new-firmware-name`'s ambiguous `no-value`, which per FWUPDATE
  /// §6.3.5 means both "never checked" *and* "checked, nothing available"
  /// on the wire and can't be told apart from that attribute alone.
  bool isCheckingForFirmware = false;

  Timer? _pollTimer;
  bool get isPolling => _pollTimer != null;

  /// Runs for as long as this session exists — see [statusMonitorInterval].
  /// Distinct from [_pollTimer], which only runs while a check/update this
  /// session itself triggered is resolving and stops once it does; this one
  /// never stops on its own, and each tick also re-evaluates
  /// [_maybeAutoCheck] so a newly-stale check-date-time gets acted on
  /// without needing to leave and reopen the printer.
  Timer? _statusMonitorTimer;

  /// Throttles [_maybeAutoCheck] so a persistently no-value/unknown
  /// check-date-time (e.g. the clock genuinely isn't set) doesn't cause a
  /// fresh Check-For-New-Printer-Firmware on every single monitor tick.
  DateTime? _lastAutoCheckAttempt;
  static const _autoCheckRetryThrottle = Duration(minutes: 1);

  void _startStatusMonitor() {
    _statusMonitorTimer?.cancel();
    _statusMonitorTimer = Timer.periodic(statusMonitorInterval, (_) => _statusMonitorTick());
  }

  Future<void> _statusMonitorTick() async {
    if (isPolling) return; // Already refreshing/watching via _pollTick.
    await refreshAttributes(silent: true);
    _maybeAutoCheck();
  }

  /// Sends Check-For-New-Printer-Firmware on its own when
  /// `printer-new-firmware-check-date-time` indicates the Printer has
  /// never checked, couldn't tell last time (`unknown`), or hasn't checked
  /// in over [autoCheckStaleThreshold] — but not otherwise, so a Printer
  /// that already checked "recently" isn't hit with a redundant request
  /// just because its status happens to be on screen.
  void _maybeAutoCheck() {
    if (_awaitingCheckResult || isPolling) return;
    final now = DateTime.now().toUtc();
    final lastAttempt = _lastAutoCheckAttempt;
    if (lastAttempt != null && now.difference(lastAttempt) < _autoCheckRetryThrottle) {
      return;
    }

    final value = _attrs[FwStatusAttr.newFirmwareCheckDateTime]?.value;
    final isStale = switch (value) {
      null || IppNoValue() || IppUnknown() => true,
      IppDateTime() => now.difference(value.toDateTimeUtc()) > autoCheckStaleThreshold,
      _ => false,
    };
    if (!isStale) return;

    _lastAutoCheckAttempt = now;
    unawaited(checkForNewFirmware(silent: true));
  }

  /// Unlike the install pipeline, FWUPDATE's Discovery phase has no
  /// `-in-progress` `printer-state-reasons` keyword of its own (§7.3 only
  /// defines that triple for the install phases) — so the only way to tell
  /// "the check I just asked for hasn't resolved yet" is to notice that
  /// `printer-new-firmware-check-date-time` hasn't changed since before the
  /// request. [_checkDateTimeBaseline] is that "before" snapshot.
  ///
  /// But per §6.3.2, check-date-time is when the Printer *attempted* the
  /// check — a conformant Printer can (and this project's does) advance it
  /// the instant the request arrives, before it has actually finished
  /// reading the repository and updating the new-firmware-* data
  /// attributes. So check-date-time changing only proves the attempt was
  /// acknowledged, not that fresh data has landed yet. [_checkGracePolls]
  /// keeps polling a few extra ticks past that point specifically to give
  /// slower-arriving data a chance to show up, rather than stopping the
  /// instant the timestamp moves.
  bool _awaitingCheckResult = false;
  String? _checkDateTimeBaseline;
  static const _checkGracePollCount = 3;
  int? _checkGracePollsRemaining;

  final List<ClientEventLogEntry> _eventLog = [];
  List<ClientEventLogEntry> get eventLog => List.unmodifiable(_eventLog);

  // --- Derived view of the last Get-Printer-Attributes response ----------

  IppAttributeGroup get _attrs =>
      _lastResponse?.printerAttributes ??
      IppAttributeGroup(IppDelimiterTag.printerAttributes, const []);

  bool get hasAttributes => _lastResponse != null;

  int? get printerState => (_attrs['printer-state']?.value as IppEnum?)?.value;

  bool? get isAcceptingJobs => (_attrs['printer-is-accepting-jobs']?.value as IppBoolean?)?.value;

  Set<String> get stateReasons =>
      _attrs['printer-state-reasons']?.values.map((v) => v.toString()).toSet() ?? {};

  String? get currentFirmwareVersion =>
      _attrs[CurrentFirmwareAttr.stringVersion]?.value.toString();

  List<String> get currentFirmwareNames =>
      _attrs[CurrentFirmwareAttr.name]?.values.map((v) => v.toString()).toList() ?? const [];

  List<String> get currentFirmwarePatches =>
      _attrs[CurrentFirmwareAttr.patches]?.values.map((v) => v.toString()).toList() ?? const [];

  Uri? get currentFirmwareInfoUri {
    final value = _attrs[FwStatusAttr.firmwareInfoUri]?.value;
    return value == null || value is IppNoValue || value is IppUnknown
        ? null
        : Uri.tryParse(value.toString());
  }

  FirmwareInfo? get newFirmware => FirmwareInfo.tryParse(_attrs);
  FwOutOfBandState get newFirmwareState => FwOutOfBandState.of(_attrs);

  DateTime? get lastCheckDateTime {
    final value = _attrs[FwStatusAttr.newFirmwareCheckDateTime]?.value;
    return value is IppDateTime ? value.toDateTimeUtc() : null;
  }

  String? get delayedUntilKeyword {
    final attr = _attrs[FwStatusAttr.newFirmwareDelayedUntil];
    return attr != null && !attr.isOutOfBand ? attr.value.toString() : null;
  }

  DateTime? get delayedUntilDateTime {
    final attr = _attrs[FwStatusAttr.newFirmwareDelayedUntilDateTime];
    return attr != null && !attr.isOutOfBand ? (attr.value as IppDateTime).toDateTimeUtc() : null;
  }

  bool supportsOperation(int operationId) {
    final response = _lastResponse;
    if (response == null) return true; // haven't asked yet — assume yes
    final ops = response.printerAttributes['operations-supported'];
    if (ops == null) return true;
    return ops.values.whereType<IppEnum>().any((e) => e.value == operationId);
  }

  bool get _hasActivePhaseOrPendingCheck {
    if (stateReasons.any((r) => r.endsWith('-in-progress'))) return true;
    if (stateReasons.contains(FwStateReason.newFirmwareInstallationDelayUntilSpecified)) {
      return true;
    }
    return false;
  }

  // --- Actions -------------------------------------------------------

  Future<void> connect() async {
    await refreshAttributes();
    _maybeAutoCheck();
    _startStatusMonitor();
  }

  /// [silent] skips the [isBusy] toggle — used by the auto-refresh timer so
  /// buttons that disable while busy don't flicker on every tick.
  Future<void> refreshAttributes({bool silent = false}) async {
    if (!silent) {
      isBusy = true;
      _notify();
    }
    try {
      final request = buildGetPrinterAttributesRequest(
        printerUri: printerUri.toString(),
        requestId: _nextRequestId++,
        requestingUserName: identity.requestingUserName,
      );
      final response = await _sendAndLog(request, 'Get-Printer-Attributes');
      _lastResponse = response;
      isConnected = response.isSuccessful;
      lastError = response.isSuccessful ? null : IppStatusCode.name(response.statusCode);
    } catch (e) {
      isConnected = false;
      lastError = '$e';
    }
    if (!silent) isBusy = false;
    _notify();
  }

  /// [silent] skips the [isBusy] toggle — used by the auto-refresh timer so
  /// buttons that disable while busy don't flicker on every tick.
  Future<void> checkForNewFirmware({bool silent = false}) async {
    isCheckingForFirmware = true;
    if (!silent) isBusy = true;
    _notify();
    try {
      _checkDateTimeBaseline = _attrs[FwStatusAttr.newFirmwareCheckDateTime]?.value.toString();
      _checkGracePollsRemaining = null;
      final request = buildCheckForNewPrinterFirmwareRequest(
        printerUri: printerUri.toString(),
        requestId: _nextRequestId++,
        requestingUserName: identity.requestingUserName,
      );
      final response = await _sendAndLog(request, 'Check-For-New-Printer-Firmware');
      lastError = response.isSuccessful ? null : IppStatusCode.name(response.statusCode);
      if (response.isSuccessful) {
        _awaitingCheckResult = true;
        _startPolling();
      } else {
        isCheckingForFirmware = false;
      }
    } catch (e) {
      lastError = '$e';
      isCheckingForFirmware = false;
    }
    if (!silent) isBusy = false;
    _notify();
  }

  Future<void> requestUpdate({String? delayUpdateUntil, DateTime? delayUpdateUntilDateTime}) async {
    isBusy = true;
    _notify();
    try {
      final request = buildUpdatePrinterFirmwareRequest(
        printerUri: printerUri.toString(),
        requestId: _nextRequestId++,
        requestingUserName: identity.requestingUserName,
        delayUpdateUntil: delayUpdateUntil,
        delayUpdateUntilDateTime: delayUpdateUntilDateTime,
      );
      final response = await _sendAndLog(request, 'Update-Printer-Firmware');
      lastError = response.isSuccessful ? null : IppStatusCode.name(response.statusCode);
      if (response.isSuccessful) _startPolling();
    } on ConflictingDelayAttributesError catch (e) {
      lastError = '$e';
    } catch (e) {
      lastError = '$e';
    }
    isBusy = false;
    _notify();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollTick());
    unawaited(_pollTick()); // Don't make the UI wait a full interval to see the first update.
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _checkGracePollsRemaining = null;
    isCheckingForFirmware = false;
    _notify();
  }

  Future<void> _pollTick() async {
    try {
      final request = buildGetPrinterAttributesRequest(
        printerUri: printerUri.toString(),
        requestId: _nextRequestId++,
        requestingUserName: identity.requestingUserName,
      );
      final response = await _sendAndLog(request, 'Get-Printer-Attributes (poll)');
      _lastResponse = response;
      isConnected = true;
      lastError = null;
      if (_awaitingCheckResult) {
        final currentCheckDateTime = _attrs[FwStatusAttr.newFirmwareCheckDateTime]?.value
            .toString();
        if (currentCheckDateTime != _checkDateTimeBaseline) {
          _awaitingCheckResult = false;
          _checkGracePollsRemaining = _checkGracePollCount;
        }
      }
      if (!_awaitingCheckResult && !_hasActivePhaseOrPendingCheck) {
        final grace = _checkGracePollsRemaining;
        if (grace == null || grace <= 0) {
          stopPolling();
        } else {
          _checkGracePollsRemaining = grace - 1;
        }
      }
    } catch (e) {
      // Deliberately not fatal: FWUPDATE §4.4/§5.2 both note the Printer
      // can become temporarily unreachable mid-update (e.g. rebooting to
      // activate new Firmware) — a conformant Client keeps polling rather
      // than reporting the update as failed.
      lastError = 'Printer temporarily unreachable, still polling: $e';
    }
    _notify();
  }

  Future<IppMessage> _sendAndLog(IppMessage request, String label) async {
    try {
      final response = await _transport.send(
        printerUri,
        request,
        basicAuthUsername: identity.basicAuthUsername,
        basicAuthPassword: identity.basicAuthPassword,
      );
      _eventLog.insert(
        0,
        ClientEventLogEntry(
          timestamp: DateTime.now(),
          label: label,
          request: request,
          response: response,
        ),
      );
      return response;
    } catch (e) {
      _eventLog.insert(
        0,
        ClientEventLogEntry(timestamp: DateTime.now(), label: label, request: request, error: e),
      );
      rethrow;
    }
  }

  bool _disposed = false;

  /// Guards against calling `notifyListeners()` on a session whose widget
  /// has already gone away — an in-flight poll tick's continuation can
  /// still run after [dispose] cancels the timer, since cancellation
  /// doesn't abort a callback already in progress.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _statusMonitorTimer?.cancel();
    _transport.close();
    super.dispose();
  }
}
