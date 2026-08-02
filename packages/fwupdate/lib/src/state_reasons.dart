/// New `printer-state-reasons` keywords defined by FWUPDATE §7.3, plus the
/// phase groupings used to drive/read the Firmware Update Phases state
/// machine from Figure 1 of the spec.
library;

/// The six phases from Figure 1 that emit `-in-progress`/`-success`/
/// `-failure` reason triples, in pipeline order. `discovery` is driven by
/// Check-For-New-Printer-Firmware (§5.1); the rest by Update-Printer-Firmware
/// (§5.2).
enum FwPhase { discovery, acquisition, validation, installation, activation, cleanup, recovery }

/// One `printer-state-reasons` keyword, and (for phase keywords) which
/// [FwPhase] and outcome it describes.
abstract final class FwStateReason {
  // §7.3.1-7.3.3, §7.3.4: conditions not tied to a specific phase outcome.
  static const firmwareRepositoryAccessError = 'firmware-repository-access-error';
  static const firmwareRepositoryUnreachable = 'firmware-repository-unreachable';
  static const newFirmwareInstallationDelayUntilSpecified =
      'new-firmware-installation-delay-until-specified';
  static const newFirmwareAvailable = 'new-firmware-available';

  // §7.3.5-7.3.7 Acquisition
  static const newFirmwareAcquisitionFailure = 'new-firmware-acquisition-failure';
  static const newFirmwareAcquisitionInProgress = 'new-firmware-acquisition-in-progress';
  static const newFirmwareAcquisitionSuccess = 'new-firmware-acquisition-success';

  // §7.3.8-7.3.10 Activation
  static const newFirmwareActivationFailure = 'new-firmware-activation-failure';
  static const newFirmwareActivationInProgress = 'new-firmware-activation-in-progress';
  static const newFirmwareActivationSuccess = 'new-firmware-activation-success';

  // §7.3.11-7.3.13 Cleanup
  static const newFirmwareCleanupFailure = 'new-firmware-cleanup-failure';
  static const newFirmwareCleanupInProgress = 'new-firmware-cleanup-in-progress';
  static const newFirmwareCleanupSuccess = 'new-firmware-cleanup-success';

  // §7.3.14-7.3.16 Installation
  static const newFirmwareInstallationFailure = 'new-firmware-installation-failure';
  static const newFirmwareInstallationInProgress = 'new-firmware-installation-in-progress';
  static const newFirmwareInstallationSuccess = 'new-firmware-installation-success';

  // §7.3.17-7.3.19 Recovery
  static const newFirmwareRecoveryFailure = 'new-firmware-recovery-failure';
  static const newFirmwareRecoveryInProgress = 'new-firmware-recovery-in-progress';
  static const newFirmwareRecoverySuccess = 'new-firmware-recovery-success';

  // §7.3.20-7.3.22 Validation
  static const newFirmwareValidationFailure = 'new-firmware-validation-failure';
  static const newFirmwareValidationInProgress = 'new-firmware-validation-in-progress';
  static const newFirmwareValidationSuccess = 'new-firmware-validation-success';

  static const all = [
    firmwareRepositoryAccessError,
    firmwareRepositoryUnreachable,
    newFirmwareInstallationDelayUntilSpecified,
    newFirmwareAvailable,
    newFirmwareAcquisitionFailure,
    newFirmwareAcquisitionInProgress,
    newFirmwareAcquisitionSuccess,
    newFirmwareActivationFailure,
    newFirmwareActivationInProgress,
    newFirmwareActivationSuccess,
    newFirmwareCleanupFailure,
    newFirmwareCleanupInProgress,
    newFirmwareCleanupSuccess,
    newFirmwareInstallationFailure,
    newFirmwareInstallationInProgress,
    newFirmwareInstallationSuccess,
    newFirmwareRecoveryFailure,
    newFirmwareRecoveryInProgress,
    newFirmwareRecoverySuccess,
    newFirmwareValidationFailure,
    newFirmwareValidationInProgress,
    newFirmwareValidationSuccess,
  ];
}

/// The `-in-progress`/`-success`/`-failure` keyword triple for one phase of
/// Figure 1's install pipeline (Acquisition, Validation, Installation,
/// Activation, Cleanup, Recovery — `discovery` has no triple of its own,
/// see [FwStateReason.newFirmwareAvailable] and the repository-error
/// reasons instead).
final class FwPhaseReasons {
  const FwPhaseReasons({
    required this.inProgress,
    required this.success,
    required this.failure,
  });

  final String inProgress;
  final String success;
  final String failure;

  static const FwPhaseReasons acquisition = FwPhaseReasons(
    inProgress: FwStateReason.newFirmwareAcquisitionInProgress,
    success: FwStateReason.newFirmwareAcquisitionSuccess,
    failure: FwStateReason.newFirmwareAcquisitionFailure,
  );

  static const FwPhaseReasons validation = FwPhaseReasons(
    inProgress: FwStateReason.newFirmwareValidationInProgress,
    success: FwStateReason.newFirmwareValidationSuccess,
    failure: FwStateReason.newFirmwareValidationFailure,
  );

  static const FwPhaseReasons installation = FwPhaseReasons(
    inProgress: FwStateReason.newFirmwareInstallationInProgress,
    success: FwStateReason.newFirmwareInstallationSuccess,
    failure: FwStateReason.newFirmwareInstallationFailure,
  );

  static const FwPhaseReasons activation = FwPhaseReasons(
    inProgress: FwStateReason.newFirmwareActivationInProgress,
    success: FwStateReason.newFirmwareActivationSuccess,
    failure: FwStateReason.newFirmwareActivationFailure,
  );

  static const FwPhaseReasons cleanup = FwPhaseReasons(
    inProgress: FwStateReason.newFirmwareCleanupInProgress,
    success: FwStateReason.newFirmwareCleanupSuccess,
    failure: FwStateReason.newFirmwareCleanupFailure,
  );

  static const FwPhaseReasons recovery = FwPhaseReasons(
    inProgress: FwStateReason.newFirmwareRecoveryInProgress,
    success: FwStateReason.newFirmwareRecoverySuccess,
    failure: FwStateReason.newFirmwareRecoveryFailure,
  );

  static const Map<FwPhase, FwPhaseReasons> byPhase = {
    FwPhase.acquisition: acquisition,
    FwPhase.validation: validation,
    FwPhase.installation: installation,
    FwPhase.activation: activation,
    FwPhase.cleanup: cleanup,
    FwPhase.recovery: recovery,
  };

  static const List<String> allKeywords = [
    FwStateReason.newFirmwareAcquisitionInProgress,
    FwStateReason.newFirmwareAcquisitionSuccess,
    FwStateReason.newFirmwareAcquisitionFailure,
    FwStateReason.newFirmwareValidationInProgress,
    FwStateReason.newFirmwareValidationSuccess,
    FwStateReason.newFirmwareValidationFailure,
    FwStateReason.newFirmwareInstallationInProgress,
    FwStateReason.newFirmwareInstallationSuccess,
    FwStateReason.newFirmwareInstallationFailure,
    FwStateReason.newFirmwareActivationInProgress,
    FwStateReason.newFirmwareActivationSuccess,
    FwStateReason.newFirmwareActivationFailure,
    FwStateReason.newFirmwareCleanupInProgress,
    FwStateReason.newFirmwareCleanupSuccess,
    FwStateReason.newFirmwareCleanupFailure,
    FwStateReason.newFirmwareRecoveryInProgress,
    FwStateReason.newFirmwareRecoverySuccess,
    FwStateReason.newFirmwareRecoveryFailure,
  ];
}
