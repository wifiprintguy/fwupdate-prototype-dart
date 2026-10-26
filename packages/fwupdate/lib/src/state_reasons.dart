/// New `printer-state-reasons` keywords defined by FWUPDATE §7.3, plus the
/// phase groupings used to drive/read the Firmware Update state machine
/// from Figure 1 ("Firmware Update Phases") and Figure 7 ("Firmware Update
/// Phases and 'printer-state-reasons' keywords") of the spec.
library;

/// The phases from §2.4 and Figure 1, in pipeline order.
///
/// * [discovery] is driven by Check-For-New-Printer-Firmware (§5.1) and has
///   no keyword of its own — its outcome is reported via
///   `firmware-update-available` or one of the repository-error reasons.
/// * [acquisition] through [activation] each report a
///   `firmware-update-<phase>` keyword while running and a
///   `firmware-update-<phase>-failed` keyword if they fail (Table 2).
/// * [recovery] runs only after one of those four phases fails, restoring
///   the previously installed Firmware. Figure 7 calls it the "Aborting
///   Phase" and reports it with `firmware-update-aborting` (§7.3.4). It has
///   no failure keyword: Figure 7 always ends it in "Aborted".
enum FwPhase { discovery, acquisition, validation, installation, activation, recovery }

/// One `printer-state-reasons` keyword from FWUPDATE §7.3.
abstract final class FwStateReason {
  // §7.3.1-7.3.2: repository conditions, reported by the Discovery phase.
  static const firmwareRepositoryAccessError = 'firmware-repository-access-error';
  static const firmwareRepositoryUnreachable = 'firmware-repository-unreachable';

  // §7.3.3-7.3.4: the unsuccessful end of a Firmware Update.
  static const firmwareUpdateAborted = 'firmware-update-aborted';
  static const firmwareUpdateAborting = 'firmware-update-aborting';

  // §7.3.5-7.3.8, 7.3.11-7.3.12, 7.3.15-7.3.16: per-phase keywords (Table 2).
  static const firmwareUpdateAcquisition = 'firmware-update-acquisition';
  static const firmwareUpdateAcquisitionFailed = 'firmware-update-acquisition-failed';
  static const firmwareUpdateActivation = 'firmware-update-activation';
  static const firmwareUpdateActivationFailed = 'firmware-update-activation-failed';
  static const firmwareUpdateInstallation = 'firmware-update-installation';
  static const firmwareUpdateInstallationFailed = 'firmware-update-installation-failed';
  static const firmwareUpdateValidation = 'firmware-update-validation';
  static const firmwareUpdateValidationFailed = 'firmware-update-validation-failed';

  // §7.3.9: new Firmware was discovered.
  static const firmwareUpdateAvailable = 'firmware-update-available';

  // §7.3.10: the successful end of a Firmware Update.
  static const firmwareUpdateCompleted = 'firmware-update-completed';

  // §7.3.13: a Firmware Update will soon begin. Also listed for the whole
  // wait of a delayed update (§5.2.1), and replaced by
  // `firmware-update-processing` when the update starts (§4.6).
  static const firmwareUpdatePending = 'firmware-update-pending';

  // §7.3.14: a Firmware Update is running (spans every phase, including
  // Recovery, until it is replaced by `-completed` or `-aborted`).
  static const firmwareUpdateProcessing = 'firmware-update-processing';

  // §7.3.17: the Printer will soon restart and likely be unreachable.
  static const restarting = 'restarting';

  static const all = [
    firmwareRepositoryAccessError,
    firmwareRepositoryUnreachable,
    firmwareUpdateAborted,
    firmwareUpdateAborting,
    firmwareUpdateAcquisition,
    firmwareUpdateAcquisitionFailed,
    firmwareUpdateActivation,
    firmwareUpdateActivationFailed,
    firmwareUpdateAvailable,
    firmwareUpdateCompleted,
    firmwareUpdateInstallation,
    firmwareUpdateInstallationFailed,
    firmwareUpdatePending,
    firmwareUpdateProcessing,
    firmwareUpdateValidation,
    firmwareUpdateValidationFailed,
    restarting,
  ];

  /// Keywords that mean a Firmware Update is scheduled, about to start, or
  /// running. A Client watching an update keeps polling while any of these
  /// is listed, and can consider the update finished once none is.
  static const updateActive = {
    firmwareUpdatePending,
    firmwareUpdateProcessing,
    firmwareUpdateAcquisition,
    firmwareUpdateValidation,
    firmwareUpdateInstallation,
    firmwareUpdateActivation,
    firmwareUpdateAborting,
    restarting,
  };

  /// The two keywords that report how the most recent Firmware Update
  /// ended. Each is listed only for an implementation-specific time (§4.6).
  static const outcomes = {firmwareUpdateCompleted, firmwareUpdateAborted};

  /// Every `firmware-update-<phase>-failed` keyword.
  static const phaseFailures = {
    firmwareUpdateAcquisitionFailed,
    firmwareUpdateValidationFailed,
    firmwareUpdateInstallationFailed,
    firmwareUpdateActivationFailed,
  };
}

/// The keywords reported for one phase of a Firmware Update (Table 2):
/// [active] while the phase runs, and [failed] if it fails. [failed] is
/// `null` for [FwPhase.recovery], which Figure 7 never shows failing.
final class FwPhaseReasons {
  const FwPhaseReasons({required this.active, this.failed});

  final String active;
  final String? failed;

  static const FwPhaseReasons acquisition = FwPhaseReasons(
    active: FwStateReason.firmwareUpdateAcquisition,
    failed: FwStateReason.firmwareUpdateAcquisitionFailed,
  );

  static const FwPhaseReasons validation = FwPhaseReasons(
    active: FwStateReason.firmwareUpdateValidation,
    failed: FwStateReason.firmwareUpdateValidationFailed,
  );

  static const FwPhaseReasons installation = FwPhaseReasons(
    active: FwStateReason.firmwareUpdateInstallation,
    failed: FwStateReason.firmwareUpdateInstallationFailed,
  );

  static const FwPhaseReasons activation = FwPhaseReasons(
    active: FwStateReason.firmwareUpdateActivation,
    failed: FwStateReason.firmwareUpdateActivationFailed,
  );

  static const FwPhaseReasons recovery = FwPhaseReasons(
    active: FwStateReason.firmwareUpdateAborting,
  );

  static const Map<FwPhase, FwPhaseReasons> byPhase = {
    FwPhase.acquisition: acquisition,
    FwPhase.validation: validation,
    FwPhase.installation: installation,
    FwPhase.activation: activation,
    FwPhase.recovery: recovery,
  };

  /// The four phases that make up the main install pipeline, in order.
  static const List<FwPhase> pipeline = [
    FwPhase.acquisition,
    FwPhase.validation,
    FwPhase.installation,
    FwPhase.activation,
  ];
}
