import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:ipp/ipp.dart';

import 'firmware_state_machine.dart';
import 'simulation_config.dart';
import 'transaction_log_entry.dart';

/// The Printer app's live state and IPP request dispatcher, in one
/// [ChangeNotifier] the UI can listen to directly.
///
/// This is the simulated Printer described in the project README: it
/// implements Get-Printer-Attributes plus the two FWUPDATE operations, and
/// its behavior is entirely driven by [config] (settable live from the
/// Simulation Control screen) rather than any real firmware/repository.
///
/// Autonomous behavior (§4.6): when [SimulationConfig.policy] is
/// [NewFirmwarePolicy.auto] and a discovery run finds new Firmware, this
/// engine starts the install pipeline itself, without waiting for an
/// Update-Printer-Firmware request — matching what the "policy" attribute
/// is supposed to mean. The other three policy keywords are reported
/// truthfully via `printer-new-firmware-policy-configured` but don't
/// trigger autonomous phases in this prototype (see README "Milestones" —
/// full policy-driven autonomy for `check`/`directed`/`download` is a
/// possible future refinement, not required to validate a Client's
/// Triggered Autonomous Firmware Update handling, which is the model this
/// project targets per FWUPDATE §4.1.3).
class PrinterEngine extends ChangeNotifier {
  PrinterEngine({this.printerName = 'FWUPDATE Sim Printer', SimulationConfig? config}) {
    _config = config ?? const SimulationConfig();
    _stateMachine = FirmwareStateMachine(this);
  }

  final String printerName;

  /// The IPP server this engine is wired to, so the Recovery/Activation
  /// mid-update-outage simulation can actually drop connections at the
  /// socket level. Set by the app's bootstrap code after both are created.
  IppServer? server;

  late final FirmwareStateMachine _stateMachine;

  SimulationConfig _config = const SimulationConfig();
  SimulationConfig get config => _config;

  /// Replaces the simulation config and immediately re-evaluates discovery
  /// (rather than waiting for a Client to ask) so the Simulation Control
  /// screen gives instant feedback when the tester flips a toggle.
  void updateConfig(SimulationConfig Function(SimulationConfig current) update) {
    _config = update(_config);
    if (!_stateMachine.isRunning) {
      _performDiscovery();
    }
    notifyListeners();
  }

  void replaceConfig(SimulationConfig newConfig) {
    _config = newConfig;
    if (!_stateMachine.isRunning) {
      _performDiscovery();
    }
    notifyListeners();
  }

  // --- Installed firmware (the "current", not "new", firmware) ---------
  //
  // Modeled as parallel lists (one entry per firmware component) to match
  // how PWG 5100.13 defines these as 1setOf attributes — see
  // [CurrentFirmwareAttr]. In practice this project's UI only ever edits a
  // single component, so [setCurrentFirmwareVersion] collapses to a
  // one-element list; a successful install (see [concludeAfterCleanup]) can
  // still carry over a multi-component identity if the "new" Firmware was
  // configured with one.

  List<String> currentFirmwareNames = ['main-controller'];
  List<String> currentFirmwarePatches = ['none'];
  List<String> currentFirmwareStringVersions = ['1.0.0'];
  List<Uint8List> currentFirmwareVersionBytes = [Uint8List.fromList(utf8.encode('1.0.0'))];

  /// The primary/first component's version string — what the Home tab and
  /// Simulation Control's edit dialog show and edit, and what
  /// [releaseNotesUri] keys off of.
  String get currentFirmwareVersion =>
      currentFirmwareStringVersions.isNotEmpty ? currentFirmwareStringVersions.first : '';

  /// Self-hosted: computed from [_serverBaseUri] rather than stored, so it's
  /// always a real, reachable link (served by [handleOtherRequest]) instead
  /// of a placeholder — falls back to a dead `example.com` URL only before
  /// the server has actually started.
  Uri get currentFirmwareInfoUri => releaseNotesUri(currentFirmwareVersion);

  void setCurrentFirmwareVersion(String version) {
    currentFirmwareStringVersions = [version];
    currentFirmwareVersionBytes = [Uint8List.fromList(utf8.encode(version))];
    notifyListeners();
  }

  // --- Self-hosted release notes ---------------------------------------

  Uri? _serverBaseUri;

  /// Called once by the app's bootstrap code after the IPP server has
  /// actually bound, so `printer-firmware-info-uri`/
  /// `printer-new-firmware-info-uri` can point at a real, reachable URL
  /// this same process serves (see [handleOtherRequest]) instead of a
  /// placeholder.
  void configureServerAddress(String host, int port) {
    _serverBaseUri = Uri(scheme: 'http', host: host, port: port);
    notifyListeners();
  }

  Uri releaseNotesUri(String version) {
    final base = _serverBaseUri ?? Uri.parse('https://example.com');
    return base.replace(path: '/release-notes/${Uri.encodeComponent(version)}');
  }

  /// Serves a minimal release-notes page for any GET request the IPP
  /// dispatcher doesn't otherwise handle, so the info-uri attributes are
  /// genuinely clickable/fetchable rather than dead links.
  Future<void> handleOtherRequest(HttpRequest request) async {
    const prefix = '/release-notes/';
    if (request.method == 'GET' && request.uri.path.startsWith(prefix)) {
      final version = Uri.decodeComponent(request.uri.path.substring(prefix.length));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_releaseNotesHtml(version));
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  String _releaseNotesHtml(String version) {
    final info = _newFirmware;
    final String body;
    if (info != null && info.stringVersions.contains(version)) {
      body =
          '<p>Urgency: ${info.urgency}</p>'
          '<p>Patches: ${info.patches.join(', ')}</p>'
          '<p>Size: ${info.kOctets} kiB</p>';
    } else if (version == currentFirmwareVersion) {
      body = '<p>This is the currently installed Firmware version.</p>';
    } else {
      body = '<p>No release notes available for this version.</p>';
    }
    return '<html><head><title>Firmware $version release notes</title></head>'
        '<body><h1>$printerName — Firmware $version</h1>$body</body></html>';
  }

  // --- Device clock -------------------------------------------------------

  /// Whether the simulated device clock is set. When false,
  /// `printer-new-firmware-check-date-time` always reports `unknown`, per
  /// FWUPDATE §6.3.2's note about `printer-current-time` being unset.
  bool clockSet = true;

  void setClockSet(bool value) {
    clockSet = value;
    notifyListeners();
  }

  // --- printer-state / printer-state-reasons ------------------------------

  int printerState = 3; // idle, per [STD92]
  bool isAcceptingJobs = true;
  final Set<String> _stateReasons = {};
  Set<String> get stateReasons => Set.unmodifiable(_stateReasons);

  FwPhase? currentPhase;

  // --- New-firmware status --------------------------------------------

  DateTime? checkDateTime;
  FirmwareInfo? _newFirmware;
  IppValue _newFirmwareOutOfBand = const IppNoValue();

  FirmwareInfo? get newFirmware => _newFirmware;
  FwOutOfBandState get newFirmwareOutOfBandState => _newFirmware != null
      ? FwOutOfBandState.none
      : (_newFirmwareOutOfBand is IppUnknown
            ? FwOutOfBandState.unknown
            : FwOutOfBandState.neverChecked);

  /// The exact `printer-new-firmware-*` attributes (§6.3.2, §6.3.5-6.3.11)
  /// this engine would put on a Get-Printer-Attributes response right now,
  /// including their out-of-band state — exposed so the UI can render each
  /// one individually and stay truthful to the wire by construction,
  /// rather than maintaining a second, potentially-drifting summary.
  List<IppAttribute> get newFirmwareStatusAttributes => [
    IppAttribute.single(FwStatusAttr.newFirmwareCheckDateTime, _checkDateTimeValue()),
    ..._newFirmwareDataAttributes(),
  ];

  String? delayedUntilKeyword;
  DateTime? delayedUntilDateTime;
  Timer? _delayTimer;
  int _discoveryRunId = 0;

  // --- Request log ----------------------------------------------------

  final List<TransactionLogEntry> _requestLog = [];
  List<TransactionLogEntry> get requestLog => List.unmodifiable(_requestLog);
  static const int _maxLogEntries = 200;

  void clearRequestLog() {
    _requestLog.clear();
    notifyListeners();
  }

  /// Resets to the state of a freshly booted Printer that has never checked
  /// for Firmware — the natural representation of the "Never checked"
  /// scenario preset (see FWUPDATE §6.3's `no-value` out-of-band wording).
  void resetToNeverChecked() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _discoveryRunId++;
    _stateMachine.cancel();
    checkDateTime = null;
    _newFirmware = null;
    _newFirmwareOutOfBand = const IppNoValue();
    _stateReasons.clear();
    printerState = 3;
    isAcceptingJobs = true;
    delayedUntilKeyword = null;
    delayedUntilDateTime = null;
    currentPhase = null;
    server?.setSimulateUnreachable(false);
    notifyListeners();
  }

  // ==================================================================
  // IPP request dispatch
  // ==================================================================

  Future<IppMessage> handleRequest(IppMessage request, HttpRequest httpRequest) async {
    final response = switch (request.operationId) {
      IppOperationId.getPrinterAttributes => _handleGetPrinterAttributes(request),
      IppOperationId.checkForNewPrinterFirmware =>
        _handleCheckForNewPrinterFirmware(request, httpRequest),
      IppOperationId.updatePrinterFirmware =>
        _handleUpdatePrinterFirmware(request, httpRequest),
      _ => IppMessage.statusResponse(
        statusCode: IppStatusCode.serverErrorOperationNotSupported,
        requestId: request.requestId,
      ),
    };
    final (versionMajor, versionMinor) = IppVersion.negotiateResponseVersion(
      request.versionMajor,
      request.versionMinor,
    );
    final versionedResponse = response.copyWithVersion(versionMajor, versionMinor);
    _logTransaction(request, versionedResponse, httpRequest);
    return versionedResponse;
  }

  void _logTransaction(IppMessage request, IppMessage response, HttpRequest httpRequest) {
    _requestLog.insert(
      0,
      TransactionLogEntry(
        timestamp: DateTime.now(),
        remoteAddress: httpRequest.connectionInfo?.remoteAddress.address ?? 'unknown',
        request: request,
        response: response,
      ),
    );
    while (_requestLog.length > _maxLogEntries) {
      _requestLog.removeLast();
    }
    notifyListeners();
  }

  /// Returns the rejection status code for [httpRequest] given
  /// [SimulationConfig.authEnforcement], or `null` if the request is
  /// allowed to proceed. Mirrors FWUPDATE §5.1/§5.2's authorization
  /// requirement.
  int? _checkAuth(HttpRequest httpRequest) {
    switch (config.authEnforcement) {
      case AuthEnforcement.off:
        return null;
      case AuthEnforcement.forceForbidden:
        return IppStatusCode.clientErrorForbidden;
      case AuthEnforcement.byRole:
        final role = _roleFromRequest(httpRequest);
        return role.isAuthorizedForFirmwareOperations ? null : role.rejectionStatusCode;
    }
  }

  SimulatedRole _roleFromRequest(HttpRequest httpRequest) {
    final header = httpRequest.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Basic ')) {
      return SimulatedRole.unauthenticated;
    }
    try {
      final decoded = utf8.decode(base64.decode(header.substring(6)));
      final separatorIndex = decoded.indexOf(':');
      final password = separatorIndex >= 0 ? decoded.substring(separatorIndex + 1) : '';
      return switch (password) {
        'administrator' => SimulatedRole.administrator,
        'operator' => SimulatedRole.operator,
        'end-user' => SimulatedRole.endUser,
        _ => SimulatedRole.unauthenticated,
      };
    } on FormatException {
      return SimulatedRole.unauthenticated;
    }
  }

  IppMessage _handleGetPrinterAttributes(IppMessage request) {
    return IppMessage.statusResponse(
      statusCode: IppStatusCode.successfulOk,
      requestId: request.requestId,
      printerAttributes: _selectRequestedAttributes(request),
    );
  }

  /// Applies the `requested-attributes` operation attribute (RFC 8011
  /// §3.2.5.1): if the Client supplied it, the response's Printer
  /// Attributes group is filtered down to just those names (or left
  /// unfiltered if it's absent, or if `'all'` is among the requested
  /// values). Unrecognized/unsupported names are simply absent from the
  /// result, per ordinary IPP practice, rather than treated as an error.
  List<IppAttribute> _selectRequestedAttributes(IppMessage request) {
    final full = _buildFullPrinterAttributes();
    final requested = request.operationAttributes['requested-attributes'];
    if (requested == null || requested.isOutOfBand) return full;

    final requestedNames = requested.values.map((v) => v.toString()).toSet();
    if (requestedNames.contains('all')) return full;

    return full.where((attribute) => requestedNames.contains(attribute.name)).toList();
  }

  IppMessage _handleCheckForNewPrinterFirmware(IppMessage request, HttpRequest httpRequest) {
    final requestId = request.requestId;
    if (!config.operations.checkForNewPrinterFirmware) {
      return IppMessage.statusResponse(
        statusCode: IppStatusCode.serverErrorOperationNotSupported,
        requestId: requestId,
        statusMessage: 'Check-For-New-Printer-Firmware is disabled on this simulated Printer',
      );
    }
    final authRejection = _checkAuth(httpRequest);
    if (authRejection != null) {
      return IppMessage.statusResponse(statusCode: authRejection, requestId: requestId);
    }

    // §6.3.2: the check-date-time is when the Printer last *attempted* to
    // check, which is now — the moment this request was received — even
    // though the actual repository query/result is simulated as taking
    // `discoveryDelay` longer. Record it before building the response so
    // the immediate ack already reflects it.
    checkDateTime = DateTime.now().toUtc();

    // Per §5.1: "The Printer responds immediately before completing the
    // check" — the firmware-data attributes below still reflect the
    // *previous* cached values; the actual (re-)discovery of what's
    // available happens after `discoveryDelay`.
    final responseAttributes = newFirmwareStatusAttributes;
    _scheduleDiscovery();

    return IppMessage.statusResponse(
      statusCode: IppStatusCode.successfulOk,
      requestId: requestId,
      printerAttributes: responseAttributes,
    );
  }

  IppMessage _handleUpdatePrinterFirmware(IppMessage request, HttpRequest httpRequest) {
    final requestId = request.requestId;
    if (!config.operations.updatePrinterFirmware) {
      return IppMessage.statusResponse(
        statusCode: IppStatusCode.serverErrorOperationNotSupported,
        requestId: requestId,
        statusMessage: 'Update-Printer-Firmware is disabled on this simulated Printer',
      );
    }
    final authRejection = _checkAuth(httpRequest);
    if (authRejection != null) {
      return IppMessage.statusResponse(statusCode: authRejection, requestId: requestId);
    }

    final op = request.operationAttributes;
    final delayKeywordAttr = op[FwOperationAttr.delayUpdateUntil];
    final delayDateTimeAttr = op[FwOperationAttr.delayUpdateUntilDateTime];

    if (delayKeywordAttr != null && delayDateTimeAttr != null) {
      // FWUPDATE §4.4: a Client "MUST NOT supply both".
      return IppMessage.statusResponse(
        statusCode: IppStatusCode.clientErrorConflictingAttributes,
        requestId: requestId,
        statusMessage:
            'delay-update-until and delay-update-until-date-time are mutually exclusive',
      );
    }

    if (_newFirmware == null) {
      // Nothing to install; per §5.2 this is still a successful no-op.
      return IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: requestId,
        statusMessage: 'No new Firmware is currently available to install',
      );
    }

    final delayKeyword = delayKeywordAttr != null && !delayKeywordAttr.isOutOfBand
        ? delayKeywordAttr.value.toString()
        : null;

    if (delayKeyword != null && delayKeyword == config.rejectedDelayUpdateUntilValue) {
      return IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOkIgnoredOrSubstitutedAttributes,
        requestId: requestId,
        statusMessage: '"$delayKeyword" is not a supported delay-update-until value here',
        unsupportedAttributes: [
          IppAttribute.single(FwOperationAttr.delayUpdateUntil, const IppUnsupported()),
        ],
      );
    }

    _delayTimer?.cancel();
    _stateReasons.remove(FwStateReason.newFirmwareInstallationDelayUntilSpecified);

    if (delayDateTimeAttr != null && !delayDateTimeAttr.isOutOfBand) {
      final target = (delayDateTimeAttr.value as IppDateTime).toDateTimeUtc();
      final wait = target.difference(DateTime.now().toUtc());
      delayedUntilDateTime = target;
      delayedUntilKeyword = null;
      if (wait > Duration.zero) {
        _stateReasons.add(FwStateReason.newFirmwareInstallationDelayUntilSpecified);
        _delayTimer = Timer(wait, _beginPipelineFromDelay);
      } else {
        _beginPipelineFromDelay();
      }
    } else if (delayKeyword != null && delayKeyword != DelayUpdateUntil.noDelay) {
      delayedUntilKeyword = delayKeyword;
      delayedUntilDateTime = null;
      final demoDelay = _demoDelayFor(delayKeyword);
      _stateReasons.add(FwStateReason.newFirmwareInstallationDelayUntilSpecified);
      if (demoDelay != null) {
        _delayTimer = Timer(demoDelay, _beginPipelineFromDelay);
      }
      // `indefinite` (demoDelay == null): stays pending until a future
      // Update-Printer-Firmware request supersedes it.
    } else {
      delayedUntilKeyword = null;
      delayedUntilDateTime = null;
      _beginPipelineFromDelay();
    }

    notifyListeners();

    return IppMessage.statusResponse(
      statusCode: IppStatusCode.successfulOk,
      requestId: requestId,
      printerAttributes: [
        if (delayedUntilKeyword != null)
          IppAttribute.single(
            FwStatusAttr.newFirmwareDelayedUntil,
            IppKeyword(delayedUntilKeyword!),
          ),
        if (delayedUntilDateTime != null)
          IppAttribute.single(
            FwStatusAttr.newFirmwareDelayedUntilDateTime,
            IppDateTime.fromDateTimeUtc(delayedUntilDateTime!),
          ),
      ],
    );
  }

  /// A short, demo-friendly stand-in for each [DelayUpdateUntil] keyword's
  /// real-world meaning ("evening", "the weekend", ...) — long enough to be
  /// observably a delay, short enough to actually watch happen. Returns
  /// `null` for `indefinite`, which has no scheduled end.
  Duration? _demoDelayFor(String keyword) => switch (keyword) {
    DelayUpdateUntil.dayTime => const Duration(seconds: 10),
    DelayUpdateUntil.evening => const Duration(seconds: 15),
    DelayUpdateUntil.night => const Duration(seconds: 20),
    DelayUpdateUntil.secondShift => const Duration(seconds: 15),
    DelayUpdateUntil.thirdShift => const Duration(seconds: 20),
    DelayUpdateUntil.weekend => const Duration(seconds: 30),
    _ => null,
  };

  void _beginPipelineFromDelay() {
    delayedUntilKeyword = null;
    delayedUntilDateTime = null;
    _stateReasons.remove(FwStateReason.newFirmwareInstallationDelayUntilSpecified);
    unawaited(_stateMachine.run());
    notifyListeners();
  }

  void _scheduleDiscovery() {
    final myRun = ++_discoveryRunId;
    Future.delayed(config.discoveryDelay, () {
      if (myRun != _discoveryRunId) return;
      // checkDateTime was already recorded when the request arrived (see
      // _handleCheckForNewPrinterFirmware) — don't overwrite it with the
      // later time this delayed result actually became available.
      _performDiscovery(recordCheckTime: false);
    });
  }

  /// Computes what the (simulated) repository has to offer and updates
  /// `printer-state-reasons`/the new-firmware attributes accordingly.
  /// [recordCheckTime] additionally stamps [checkDateTime] to now — used
  /// for the Simulation Control "instant feedback" path (§4.2/§6.3.2 don't
  /// apply there since no Client actually asked), but skipped when this is
  /// called after a real Check-For-New-Printer-Firmware request's delay,
  /// since that request's receipt time was already recorded.
  void _performDiscovery({bool recordCheckTime = true}) {
    if (recordCheckTime) {
      checkDateTime = DateTime.now().toUtc();
    }
    _stateReasons
      ..remove(FwStateReason.newFirmwareAvailable)
      ..remove(FwStateReason.firmwareRepositoryUnreachable)
      ..remove(FwStateReason.firmwareRepositoryAccessError);

    switch (config.repositoryState) {
      case RepositoryState.unreachable:
        _stateReasons.add(FwStateReason.firmwareRepositoryUnreachable);
        _newFirmware = null;
        _newFirmwareOutOfBand = const IppUnknown();
      case RepositoryState.accessError:
        _stateReasons.add(FwStateReason.firmwareRepositoryAccessError);
        _newFirmware = null;
        _newFirmwareOutOfBand = const IppUnknown();
      case RepositoryState.reachable:
        if (config.firmwareAvailable && config.firmwareInfo != null) {
          _newFirmware = config.firmwareInfo;
          _newFirmwareOutOfBand = const IppNoValue();
          _stateReasons.add(FwStateReason.newFirmwareAvailable);
          if (config.policy == NewFirmwarePolicy.auto && !_stateMachine.isRunning) {
            unawaited(_stateMachine.run());
          }
        } else {
          _newFirmware = null;
          _newFirmwareOutOfBand = const IppNoValue();
        }
    }
    notifyListeners();
  }

  IppValue _checkDateTimeValue() {
    if (checkDateTime == null) return const IppNoValue();
    if (!clockSet) return const IppUnknown();
    return IppDateTime.fromDateTimeUtc(checkDateTime!);
  }

  List<IppAttribute> _newFirmwareDataAttributes() {
    final info = _newFirmware;
    if (info == null) return buildOutOfBandFirmwareDataAttributes(_newFirmwareOutOfBand);
    // Self-host the info-uri (see [releaseNotesUri]) unless the tester
    // explicitly set one via the Simulation Control edit dialog.
    if (info.infoUri != null) return info.toAttributes();
    final version = info.stringVersions.isNotEmpty ? info.stringVersions.first : 'unknown';
    return FirmwareInfo(
      names: info.names,
      patches: info.patches,
      kOctets: info.kOctets,
      stringVersions: info.stringVersions,
      urgency: info.urgency,
      versions: info.versions,
      infoUri: releaseNotesUri(version),
    ).toAttributes();
  }

  List<IppAttribute> _buildFullPrinterAttributes() {
    final reasons = _stateReasons.isEmpty ? const ['none'] : _stateReasons.toList();
    final supportedOps = [
      const IppEnum(IppOperationId.getPrinterAttributes),
      if (config.operations.checkForNewPrinterFirmware)
        const IppEnum(IppOperationId.checkForNewPrinterFirmware),
      if (config.operations.updatePrinterFirmware)
        const IppEnum(IppOperationId.updatePrinterFirmware),
    ];

    return [
      IppAttribute.single('printer-name', IppName(printerName)),
      IppAttribute.single('printer-state', IppEnum(printerState)),
      IppAttribute('printer-state-reasons', reasons.map(IppKeyword.new).toList()),
      IppAttribute.single('printer-is-accepting-jobs', IppBoolean(isAcceptingJobs)),
      IppAttribute('operations-supported', supportedOps),
      IppAttribute.single('ipp-features-supported', const IppKeyword(ippFeatureFwupdate)),
      IppAttribute.single(
        FwStatusAttr.firmwareInfoUri,
        IppUri(currentFirmwareInfoUri.toString()),
      ),
      IppAttribute(CurrentFirmwareAttr.name, currentFirmwareNames.map(IppName.new).toList()),
      IppAttribute(
        CurrentFirmwareAttr.patches,
        currentFirmwarePatches.map(IppText.new).toList(),
      ),
      IppAttribute(
        CurrentFirmwareAttr.stringVersion,
        currentFirmwareStringVersions.map(IppText.new).toList(),
      ),
      IppAttribute(
        CurrentFirmwareAttr.version,
        currentFirmwareVersionBytes.map(IppOctetString.new).toList(),
      ),
      IppAttribute(
        FwDescriptionAttr.delayUpdateUntilSupported,
        DelayUpdateUntil.all.map(IppKeyword.new).toList(),
      ),
      IppAttribute.single(FwDescriptionAttr.newFirmwarePolicyConfigured, IppKeyword(config.policy)),
      IppAttribute(
        FwDescriptionAttr.newFirmwarePolicySupported,
        NewFirmwarePolicy.all.map(IppKeyword.new).toList(),
      ),
      IppAttribute.single(
        FwDescriptionAttr.firmwareRepositoryUriConfigured,
        const IppUri('https://example.com/fw-sim/repository'),
      ),
      IppAttribute(FwDescriptionAttr.firmwareRepositoryUriSupported, const [
        IppUri('https://example.com/fw-sim/repository'),
      ]),
      if (delayedUntilKeyword != null)
        IppAttribute.single(
          FwStatusAttr.newFirmwareDelayedUntil,
          IppKeyword(delayedUntilKeyword!),
        ),
      if (delayedUntilDateTime != null)
        IppAttribute.single(
          FwStatusAttr.newFirmwareDelayedUntilDateTime,
          IppDateTime.fromDateTimeUtc(delayedUntilDateTime!),
        ),
      ...newFirmwareStatusAttributes,
    ];
  }

  // --- Hooks used by FirmwareStateMachine ------------------------------
  // These mutate private state but must be callable from
  // firmware_state_machine.dart, so they're public methods rather than
  // exposing the fields themselves.

  void beginPipeline() {
    _stateReasons
      ..removeAll(FwPhaseReasons.allKeywords)
      ..remove(FwStateReason.firmwareUpdateSuccess)
      ..remove(FwStateReason.firmwareUpdateFailure)
      // Spans the whole Acquisition-through-Cleanup run — added once here,
      // removed once in [concludeAfterCleanup].
      ..add(FwStateReason.firmwareUpdateInProgress);
    printerState = 5; // stopped, per §5.2's body text
    isAcceptingJobs = false;
    currentPhase = null;
    notifyListeners();
  }

  void setPhaseInProgress(FwPhase phase, String inProgressReason) {
    currentPhase = phase;
    _stateReasons.add(inProgressReason);
    notifyListeners();
  }

  void setPhaseResult(
    FwPhase phase,
    String inProgressReason,
    String resultReason, {
    required bool succeeded,
  }) {
    _stateReasons
      ..remove(inProgressReason)
      ..add(resultReason);
    if (!succeeded) {
      _stateReasons.add(FwStateReason.firmwareUpdateFailure);
    }
    notifyListeners();
  }

  void beginOutage() {
    server?.setSimulateUnreachable(true);
    debugOnUnreachableChanged?.call(true);
    notifyListeners();
  }

  void endOutage() {
    server?.setSimulateUnreachable(false);
    debugOnUnreachableChanged?.call(false);
    notifyListeners();
  }

  /// Test-only hook: notified whenever [beginOutage]/[endOutage] run, so
  /// tests can assert on the mid-update-outage simulation without standing
  /// up a real [IppServer].
  void Function(bool unreachable)? debugOnUnreachableChanged;

  /// Test-only: runs the install pipeline and waits for it to finish,
  /// instead of the normal fire-and-forget path used by the real
  /// Update-Printer-Firmware handler and the `auto` policy.
  @visibleForTesting
  Future<void> debugRunPipelineToCompletion() => _stateMachine.run();

  /// Ends the pipeline as part of the same call that resolves the Cleanup
  /// phase — deliberately one atomic engine mutation rather than two
  /// separate ones (resolve Cleanup, then separately conclude), and
  /// deliberately in this order: the new `printer-firmware-*` values (and
  /// clearing `printer-new-firmware-*` back to no-value) are written
  /// *before* `new-firmware-cleanup-in-progress` is removed from
  /// `printer-state-reasons`. A Client/test polling until no `-in-progress`
  /// reason remains must never be able to observe that "done" signal one
  /// beat before the data it implies is actually in place — with both
  /// mutations happening inside one synchronous function (rather than
  /// across two, separated by whatever awaited the Cleanup phase's own
  /// completion), there is no `notifyListeners()`/HTTP response that could
  /// land in between the two.
  ///
  /// Also where `firmware-update-in-progress` (added once, back in
  /// [beginPipeline]) finally gets removed, and where the consolidated
  /// `firmware-update-success`/`-failure` keywords are decided:
  /// `-success` lands (replacing every per-phase `-success` keyword
  /// accumulated during the run) whenever Cleanup itself succeeds, and
  /// `-failure` lands whenever it doesn't — independently of whether an
  /// earlier phase already added `-failure` on its own via
  /// [setPhaseResult], since both can legitimately describe the same run
  /// (e.g. Installation failed, Recovery fixed it, Cleanup still succeeded).
  void concludeAfterCleanup({required bool cleanupSucceeded, required bool installedSuccessfully}) {
    if (installedSuccessfully) {
      final info = _newFirmware;
      if (info != null) {
        // The newly-installed Firmware's full identity becomes the new
        // "currently installed" one — not just its version string.
        // currentFirmwareInfoUri is derived from currentFirmwareVersion
        // (see its getter), so this alone keeps it correct too.
        if (info.names.isNotEmpty) currentFirmwareNames = List.of(info.names);
        if (info.patches.isNotEmpty) currentFirmwarePatches = List.of(info.patches);
        if (info.stringVersions.isNotEmpty) {
          currentFirmwareStringVersions = List.of(info.stringVersions);
        }
        if (info.versions.isNotEmpty) currentFirmwareVersionBytes = List.of(info.versions);
      }
      _newFirmware = null;
      _newFirmwareOutOfBand = const IppNoValue();
      checkDateTime = null;
      _stateReasons.remove(FwStateReason.newFirmwareAvailable);
    }

    _stateReasons
      ..remove(FwStateReason.newFirmwareCleanupInProgress)
      ..add(
        cleanupSucceeded
            ? FwStateReason.newFirmwareCleanupSuccess
            : FwStateReason.newFirmwareCleanupFailure,
      );
    if (!cleanupSucceeded) {
      _stateReasons.add(FwStateReason.firmwareUpdateFailure);
    }

    // firmware-update-in-progress spans the whole run (see [beginPipeline])
    // and ends here, regardless of outcome.
    _stateReasons.remove(FwStateReason.firmwareUpdateInProgress);
    if (cleanupSucceeded) {
      // Replace the accumulated per-phase "-success" trail with the single
      // consolidated signal, so the reasons set doesn't stay cluttered
      // once the run is over.
      _stateReasons
        ..removeAll(FwPhaseReasons.allSuccessKeywords)
        ..add(FwStateReason.firmwareUpdateSuccess);
    }

    currentPhase = null;
    printerState = 3; // idle
    isAcceptingJobs = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _stateMachine.cancel();
    super.dispose();
  }
}
