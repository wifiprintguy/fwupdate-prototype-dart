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
  }) : displayName = displayName ?? printerUri.host;

  final Uri printerUri;
  final String displayName;
  final SimulatedIdentity identity;

  /// How often to re-fetch attributes while a check/update is outstanding.
  /// Overridable so tests don't have to wait out a production-grade
  /// cadence to observe a fast simulated pipeline complete.
  final Duration pollInterval;

  final IppClientTransport _transport = IppClientTransport();
  int _nextRequestId = 1;

  IppMessage? _lastResponse;
  bool isConnected = false;
  bool isBusy = false;
  String? lastError;

  Timer? _pollTimer;
  bool get isPolling => _pollTimer != null;

  /// Unlike the install pipeline, FWUPDATE's Discovery phase has no
  /// `-in-progress` `printer-state-reasons` keyword of its own (§7.3 only
  /// defines that triple for the install phases) — so the only way to tell
  /// "the check I just asked for hasn't resolved yet" is to notice that
  /// `printer-new-firmware-check-date-time` hasn't changed since before the
  /// request. [_checkDateTimeBaseline] is that "before" snapshot.
  bool _awaitingCheckResult = false;
  String? _checkDateTimeBaseline;

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

  Future<void> connect() => refreshAttributes();

  Future<void> refreshAttributes() async {
    isBusy = true;
    _notify();
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
    isBusy = false;
    _notify();
  }

  Future<void> checkForNewFirmware() async {
    isBusy = true;
    _notify();
    try {
      _checkDateTimeBaseline = _attrs[FwStatusAttr.newFirmwareCheckDateTime]?.value.toString();
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
      }
    } catch (e) {
      lastError = '$e';
    }
    isBusy = false;
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
        }
      }
      if (!_awaitingCheckResult && !_hasActivePhaseOrPendingCheck) {
        stopPolling();
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
    _transport.close();
    super.dispose();
  }
}
