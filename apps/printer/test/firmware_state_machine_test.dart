import 'package:flutter_test/flutter_test.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:fwupdate_printer/printer_state.dart';
import 'package:fwupdate_printer/simulation_config.dart';

void main() {
  group('FirmwareStateMachine (via PrinterEngine)', () {
    late PrinterEngine engine;

    setUp(() {
      engine = PrinterEngine();
    });

    test('a full successful run clears new-firmware attributes and bumps the version', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '2.0.0',
            urgency: NewFirmwareUrgency.security,
          ),
          phaseDuration: const Duration(milliseconds: 10),
        ),
      );
      // updateConfig/replaceConfig already ran a synchronous discovery pass.
      expect(engine.newFirmware, isNotNull);
      expect(engine.stateReasons, contains(FwStateReason.newFirmwareAvailable));

      await engine.debugRunPipelineToCompletion();

      expect(engine.newFirmware, isNull);
      expect(engine.currentFirmwareVersion, '2.0.0');
      expect(engine.printerState, 3);
      expect(engine.isAcceptingJobs, isTrue);
      expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareAvailable)));
      expect(
        engine.stateReasons,
        contains(FwStateReason.newFirmwareInstallationSuccess),
      );
    });

    test('a failed phase runs Recovery then Cleanup, and does not bump the version', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '2.0.0',
            urgency: NewFirmwareUrgency.security,
          ),
          phaseOutcomes: const {
            FwPhase.acquisition: PhaseOutcome.succeed,
            FwPhase.validation: PhaseOutcome.succeed,
            FwPhase.installation: PhaseOutcome.fail,
            FwPhase.activation: PhaseOutcome.succeed,
            FwPhase.cleanup: PhaseOutcome.succeed,
            FwPhase.recovery: PhaseOutcome.succeed,
          },
          phaseDuration: const Duration(milliseconds: 10),
        ),
      );

      await engine.debugRunPipelineToCompletion();

      expect(engine.currentFirmwareVersion, '1.0.0');
      expect(engine.newFirmware, isNotNull, reason: 'firmware stays available for a retry');
      expect(
        engine.stateReasons,
        containsAll([
          FwStateReason.newFirmwareInstallationFailure,
          FwStateReason.newFirmwareRecoverySuccess,
          FwStateReason.newFirmwareCleanupSuccess,
        ]),
      );
    });

    test('mid-Activation outage marks the server unreachable and clears it afterward', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '2.0.0',
            urgency: NewFirmwareUrgency.bugfix,
          ),
          phaseDuration: const Duration(milliseconds: 10),
          midUpdateOutageDuringActivation: const Duration(milliseconds: 20),
        ),
      );

      final unreachableDuringOutage = <bool>[];
      engine.debugOnUnreachableChanged = unreachableDuringOutage.add;

      await engine.debugRunPipelineToCompletion();

      expect(unreachableDuringOutage, contains(true));
      expect(unreachableDuringOutage.last, isFalse);
    });

    test('resetToNeverChecked clears all new-firmware state', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '2.0.0',
            urgency: NewFirmwareUrgency.bugfix,
          ),
        ),
      );
      expect(engine.newFirmware, isNotNull);

      engine.resetToNeverChecked();

      expect(engine.newFirmware, isNull);
      expect(engine.newFirmwareOutOfBandState, FwOutOfBandState.neverChecked);
      expect(engine.checkDateTime, isNull);
      expect(engine.stateReasons, isEmpty);
    });
  });
}
