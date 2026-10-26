import 'package:fwupdate/fwupdate.dart';

/// What the Printer should do when it "checks" its (simulated) Firmware
/// Repository — FWUPDATE §7.3.1/§7.3.2 plus the ordinary success case.
enum RepositoryState { reachable, unreachable, accessError }

/// How one phase of a Firmware Update (Figures 1 and 7) should resolve.
/// [FwPhase.recovery] only honors [succeed] and [hang]: Figure 7 always ends
/// it in "Aborted", so a `fail` outcome there is treated as [succeed].
enum PhaseOutcome { succeed, fail, hang }

/// How the Printer should react to Check-For-New-Printer-Firmware /
/// Update-Printer-Firmware requests with respect to the Authenticated
/// User's role (FWUPDATE §5.1/§5.2). See [SimulatedRole] in package:fwupdate
/// for the roles the Client app's Identity screen can send.
enum AuthEnforcement {
  /// Any requester is allowed (no role check) — the default so a fresh
  /// Printer instance is easy to talk to.
  off,

  /// Reject unless the requester declared Operator/Administrator, using the
  /// specific status code FWUPDATE §5.1/§5.2 ties to each rejected role.
  byRole,

  /// Reject every request with `client-error-forbidden`, regardless of
  /// role — exercises the one rejection code that isn't naturally reachable
  /// by picking an unauthorized role (see package:fwupdate's
  /// `status_codes.dart` for why `forbidden` needs its own toggle).
  forceForbidden,
}

/// Whether each FWUPDATE operation is available at all. Turning one off
/// tests a Client talking to a printer that doesn't (fully) implement this
/// specification — `operations-supported` stops listing it, and if the
/// Client asks anyway it gets `server-error-operation-not-supported`.
final class OperationAvailability {
  const OperationAvailability({
    this.checkForNewPrinterFirmware = true,
    this.updatePrinterFirmware = true,
  });

  final bool checkForNewPrinterFirmware;
  final bool updatePrinterFirmware;

  OperationAvailability copyWith({
    bool? checkForNewPrinterFirmware,
    bool? updatePrinterFirmware,
  }) => OperationAvailability(
    checkForNewPrinterFirmware:
        checkForNewPrinterFirmware ?? this.checkForNewPrinterFirmware,
    updatePrinterFirmware: updatePrinterFirmware ?? this.updatePrinterFirmware,
  );
}

/// Every fault this project's Printer app can inject, bundled into one
/// object so Simulation Control screens/presets can replace it wholesale.
///
/// This intentionally does *not* include a "never checked" or "clock unset
/// forever" flag as persistent state — "never checked" is just what
/// [PrinterEngine] looks like before its first discovery run (see
/// `resetToNeverChecked()`), and clock state is tracked as engine state
/// (toggled independently of scenario) rather than simulation config, since
/// it's a device property, not a fault being injected into one operation.
final class SimulationConfig {
  const SimulationConfig({
    this.firmwareAvailable = false,
    this.firmwareInfo,
    this.repositoryState = RepositoryState.reachable,
    this.phaseOutcomes = const {
      FwPhase.acquisition: PhaseOutcome.succeed,
      FwPhase.validation: PhaseOutcome.succeed,
      FwPhase.installation: PhaseOutcome.succeed,
      FwPhase.activation: PhaseOutcome.succeed,
      FwPhase.recovery: PhaseOutcome.succeed,
    },
    this.phaseDuration = const Duration(seconds: 7),
    this.discoveryDelay = const Duration(seconds: 2),
    this.noticeDuration = const Duration(seconds: 3),
    this.outcomeRetention = const Duration(seconds: 60),
    this.midUpdateOutageDuringActivation = Duration.zero,
    this.stopsAcceptingJobsDuringUpdate = true,
    this.authEnforcement = AuthEnforcement.off,
    this.operations = const OperationAvailability(),
    this.policy = NewFirmwarePolicy.directed,
    this.rejectedDelayUpdateUntilValue,
  });

  /// Whether the simulated repository currently has new Firmware.
  final bool firmwareAvailable;

  /// The Firmware to describe when [firmwareAvailable] is true and
  /// [repositoryState] is [RepositoryState.reachable]. Required in that
  /// combination (enforced by [PrinterEngine]).
  final FirmwareInfo? firmwareInfo;

  final RepositoryState repositoryState;

  /// Outcome for each phase of a Firmware Update. [FwPhase.discovery] is
  /// governed by [repositoryState] instead and ignored here.
  final Map<FwPhase, PhaseOutcome> phaseOutcomes;

  /// How long each phase stays `-in-progress` before resolving (ignored for
  /// phases configured to [PhaseOutcome.hang]). Defaults to 7s — long
  /// enough (5-10s is the realistic range for an actual phase) that each
  /// of Acquisition/Validation/Installation/Activation/Cleanup is visible
  /// as its own step while polling, rather than the whole pipeline
  /// finishing in a blink. Recovery (`firmware-update-aborting`) uses the
  /// same duration.
  final Duration phaseDuration;

  /// How long a Check-For-New-Printer-Firmware request takes to actually
  /// resolve after the Printer acknowledges it (§5.1: "The Printer responds
  /// immediately before completing the check") — long enough that a Client
  /// under test has to poll at least once to see the result.
  final Duration discoveryDelay;

  /// How long the Printer announces something before it happens: how long
  /// `firmware-update-pending` (§7.3.13) is listed before an immediate
  /// update starts, and how long `restarting` (§7.3.17) is listed before a
  /// simulated reboot takes the Printer offline. Long enough for a polling
  /// Client to see each announcement at least once.
  final Duration noticeDuration;

  /// How long `firmware-update-completed` or `firmware-update-aborted`
  /// stays listed after an update ends. §4.6 leaves this duration
  /// "implementation specific". A new Update-Printer-Firmware or
  /// Check-For-New-Printer-Firmware request also clears it.
  final Duration outcomeRetention;

  /// If non-zero, the Printer lists `restarting` once Activation finishes
  /// and then becomes unreachable at the socket level (see
  /// `IppServer.setSimulateUnreachable`) for this long, simulating a device
  /// reboot (FWUPDATE §4.5 note, Figure 7). Also reported to Clients as
  /// `printer-new-firmware-offline-time` (§6.3.9), which is 0 when this is
  /// zero.
  final Duration midUpdateOutageDuringActivation;

  /// Whether the Printer sets `printer-state` to 'stopped' and
  /// `printer-is-accepting-jobs` to false while a Firmware Update runs.
  /// §4.6 makes this conditional on the Printer being unable to accept Jobs
  /// during the update.
  final bool stopsAcceptingJobsDuringUpdate;

  final AuthEnforcement authEnforcement;
  final OperationAvailability operations;

  /// `printer-new-firmware-policy-configured` (§6.2.2) — reported to
  /// Clients, and drives whether [PrinterEngine] starts phases on its own
  /// once Firmware is discovered (see [PrinterEngine]'s class docs).
  final String policy;

  /// If set, an Update-Printer-Firmware request naming this
  /// `delay-update-until` keyword is rejected as unsupported (Group 3 /
  /// §5.2.3's reference to [STD92] §4.1.7) instead of being honored.
  final String? rejectedDelayUpdateUntilValue;

  SimulationConfig copyWith({
    bool? firmwareAvailable,
    FirmwareInfo? firmwareInfo,
    bool clearFirmwareInfo = false,
    RepositoryState? repositoryState,
    Map<FwPhase, PhaseOutcome>? phaseOutcomes,
    Duration? phaseDuration,
    Duration? discoveryDelay,
    Duration? noticeDuration,
    Duration? outcomeRetention,
    Duration? midUpdateOutageDuringActivation,
    bool? stopsAcceptingJobsDuringUpdate,
    AuthEnforcement? authEnforcement,
    OperationAvailability? operations,
    String? policy,
    String? rejectedDelayUpdateUntilValue,
    bool clearRejectedDelayUpdateUntilValue = false,
  }) {
    return SimulationConfig(
      firmwareAvailable: firmwareAvailable ?? this.firmwareAvailable,
      firmwareInfo: clearFirmwareInfo ? null : (firmwareInfo ?? this.firmwareInfo),
      repositoryState: repositoryState ?? this.repositoryState,
      phaseOutcomes: phaseOutcomes ?? this.phaseOutcomes,
      phaseDuration: phaseDuration ?? this.phaseDuration,
      discoveryDelay: discoveryDelay ?? this.discoveryDelay,
      noticeDuration: noticeDuration ?? this.noticeDuration,
      outcomeRetention: outcomeRetention ?? this.outcomeRetention,
      midUpdateOutageDuringActivation:
          midUpdateOutageDuringActivation ?? this.midUpdateOutageDuringActivation,
      stopsAcceptingJobsDuringUpdate:
          stopsAcceptingJobsDuringUpdate ?? this.stopsAcceptingJobsDuringUpdate,
      authEnforcement: authEnforcement ?? this.authEnforcement,
      operations: operations ?? this.operations,
      policy: policy ?? this.policy,
      rejectedDelayUpdateUntilValue: clearRejectedDelayUpdateUntilValue
          ? null
          : (rejectedDelayUpdateUntilValue ?? this.rejectedDelayUpdateUntilValue),
    );
  }
}
