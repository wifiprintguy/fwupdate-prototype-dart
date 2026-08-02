import 'package:fwupdate/fwupdate.dart';

import 'printer_state.dart';
import 'simulation_config.dart';

/// A one-tap bundle of [SimulationConfig] (plus, where needed, engine-level
/// resets) for a commonly-wanted test scenario. Still just a starting
/// point — Simulation Control leaves every toggle editable afterward.
final class ScenarioPreset {
  const ScenarioPreset({required this.name, required this.description, required this.apply});

  final String name;
  final String description;
  final void Function(PrinterEngine engine) apply;
}

final _securityFirmware = FirmwareInfo.simple(
  name: 'main-controller',
  stringVersion: '2.4.1',
  urgency: NewFirmwareUrgency.security,
  patch: 'CVE-2026-41210',
  infoUri: Uri.parse('https://example.com/fw-sim/release-notes/2.4.1'),
);

const _allSucceed = {
  FwPhase.acquisition: PhaseOutcome.succeed,
  FwPhase.validation: PhaseOutcome.succeed,
  FwPhase.installation: PhaseOutcome.succeed,
  FwPhase.activation: PhaseOutcome.succeed,
  FwPhase.cleanup: PhaseOutcome.succeed,
  FwPhase.recovery: PhaseOutcome.succeed,
};

final List<ScenarioPreset> scenarioPresets = [
  ScenarioPreset(
    name: 'Happy path — security update',
    description:
        'New Firmware is available with urgency=security; every phase succeeds on a '
        'realistic timeline.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: _securityFirmware,
          phaseOutcomes: _allSucceed,
        ),
      );
    },
  ),
  ScenarioPreset(
    name: 'No update available',
    description: 'Repository is reachable but has nothing newer than what is installed.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(const SimulationConfig(firmwareAvailable: false));
    },
  ),
  ScenarioPreset(
    name: 'Repository unreachable',
    description:
        "Printer can't connect to its configured Firmware Repository at all "
        '(§7.3.2 firmware-repository-unreachable).',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        const SimulationConfig(repositoryState: RepositoryState.unreachable),
      );
    },
  ),
  ScenarioPreset(
    name: 'Repository access error',
    description:
        'Repository is reachable but the download itself fails — bad TLS cert, missing '
        'file, forbidden (§7.3.1 firmware-repository-access-error).',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(const SimulationConfig(repositoryState: RepositoryState.accessError));
    },
  ),
  ScenarioPreset(
    name: 'Never checked',
    description:
        'Fresh-boot state: every printer-new-firmware-* attribute reports no-value, as if '
        'no check has ever run.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
    },
  ),
  ScenarioPreset(
    name: 'Clock not set',
    description:
        'printer-current-time is unset, so printer-new-firmware-check-date-time reports '
        'unknown even after checking (§6.3.2 note).',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(false);
      engine.replaceConfig(
        SimulationConfig(firmwareAvailable: true, firmwareInfo: _securityFirmware),
      );
    },
  ),
  ScenarioPreset(
    name: 'Acquisition fails',
    description: 'The Acquisition phase fails, Recovery runs and succeeds, then Cleanup runs.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: _securityFirmware,
          phaseOutcomes: {..._allSucceed, FwPhase.acquisition: PhaseOutcome.fail},
        ),
      );
    },
  ),
  ScenarioPreset(
    name: 'Installation fails, recovery also fails',
    description:
        'The Installation phase fails and the subsequent Recovery attempt fails too — '
        'the worst case a Client has to surface clearly.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: _securityFirmware,
          phaseOutcomes: {
            ..._allSucceed,
            FwPhase.installation: PhaseOutcome.fail,
            FwPhase.recovery: PhaseOutcome.fail,
          },
        ),
      );
    },
  ),
  ScenarioPreset(
    name: 'Reboot mid-activation',
    description:
        'The Printer goes dark at the socket level for 15s during Activation, simulating a '
        'real device reboot (§4.4/§5.2 note) — the Client must treat this as transient.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: _securityFirmware,
          phaseOutcomes: _allSucceed,
          midUpdateOutageDuringActivation: const Duration(seconds: 15),
        ),
      );
    },
  ),
  ScenarioPreset(
    name: 'Unauthorized Client',
    description:
        'Auth enforcement is on; any requester that is not Operator/Administrator gets '
        'rejected with the status code FWUPDATE §5.1/§5.2 specifies for their role.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: _securityFirmware,
          authEnforcement: AuthEnforcement.byRole,
        ),
      );
    },
  ),
  ScenarioPreset(
    name: 'Delayed install, indefinite',
    description:
        "A Client's delay-update-until=indefinite request is accepted and held pending — "
        'the Printer reports new-firmware-installation-delay-until-specified until a new '
        'request supersedes it.',
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        SimulationConfig(firmwareAvailable: true, firmwareInfo: _securityFirmware),
      );
    },
  ),
  ScenarioPreset(
    name: 'Operation not supported',
    description:
        'Both FWUPDATE operations are removed from operations-supported, simulating a '
        "printer that doesn't implement this specification at all.",
    apply: (engine) {
      engine.resetToNeverChecked();
      engine.setClockSet(true);
      engine.replaceConfig(
        const SimulationConfig(
          operations: OperationAvailability(
            checkForNewPrinterFirmware: false,
            updatePrinterFirmware: false,
          ),
        ),
      );
    },
  ),
];
