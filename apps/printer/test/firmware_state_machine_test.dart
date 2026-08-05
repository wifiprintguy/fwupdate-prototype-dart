import 'package:flutter_test/flutter_test.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:fwupdate_printer/printer_state.dart';
import 'package:fwupdate_printer/simulation_config.dart';
import 'package:ipp/ipp.dart';

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
      expect(engine.currentFirmwareNames, ['main-controller']);
      expect(engine.currentFirmwarePatches, ['none']);
      expect(engine.printerState, 3);
      expect(engine.isAcceptingJobs, isTrue);
      expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareAvailable)));
      // The per-phase "-success" trail is swept in favor of the single
      // consolidated signal once the whole run finishes successfully.
      expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareInstallationSuccess)));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateInProgress)));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateSuccess));
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
      expect(engine.currentFirmwareNames, ['main-controller'], reason: 'unchanged on failure');
      expect(engine.newFirmware, isNotNull, reason: 'firmware stays available for a retry');
      // Installation's own failure keyword persists (per-phase failures
      // aren't swept), but Recovery/Cleanup's "-success" keywords are —
      // replaced by the consolidated firmware-update-success, which can
      // coexist with firmware-update-failure: something failed along the
      // way, but the run still finished (Recovery fixed it, Cleanup ran).
      expect(engine.stateReasons, contains(FwStateReason.newFirmwareInstallationFailure));
      expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareRecoverySuccess)));
      expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareCleanupSuccess)));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateFailure));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateSuccess));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateInProgress)));
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

    test('a successful install carries over the new patches, not just the version', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'wifi-module',
            stringVersion: '3.1.4',
            urgency: NewFirmwareUrgency.security,
            patch: 'CVE-2026-41210',
          ),
          phaseDuration: const Duration(milliseconds: 10),
        ),
      );

      await engine.debugRunPipelineToCompletion();

      expect(engine.currentFirmwareNames, ['wifi-module']);
      expect(engine.currentFirmwarePatches, ['CVE-2026-41210']);
      expect(engine.currentFirmwareVersion, '3.1.4');
    });

    test('setCurrentFirmwareVersion collapses to a single component', () {
      engine.setCurrentFirmwareVersion('9.9.9');

      expect(engine.currentFirmwareVersion, '9.9.9');
      expect(engine.currentFirmwareStringVersions, ['9.9.9']);
      expect(engine.currentFirmwareVersionBytes, hasLength(1));
    });

    test('newFirmwareStatusAttributes exposes every printer-new-firmware-* attribute', () {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '5.5.5',
            urgency: NewFirmwareUrgency.feature,
          ),
        ),
      );

      final names = engine.newFirmwareStatusAttributes.map((a) => a.name).toSet();
      expect(names, {
        FwStatusAttr.newFirmwareCheckDateTime,
        FwStatusAttr.newFirmwareInfoUri,
        FwStatusAttr.newFirmwareKOctets,
        FwStatusAttr.newFirmwareName,
        FwStatusAttr.newFirmwarePatches,
        FwStatusAttr.newFirmwareStringVersion,
        FwStatusAttr.newFirmwareUrgency,
        FwStatusAttr.newFirmwareVersion,
      });
      final checkDateTimeAttr = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareCheckDateTime,
      );
      expect(checkDateTimeAttr.value, isA<IppDateTime>());
      final nameAttr = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareName,
      );
      expect(nameAttr.values.map((v) => v.toString()), ['main-controller']);
    });

    test(
      'a successful install clears new-firmware-available and every data attribute to '
      'no-value',
      () async {
        engine.replaceConfig(
          SimulationConfig(
            firmwareAvailable: true,
            firmwareInfo: FirmwareInfo.simple(
              name: 'main-controller',
              stringVersion: '6.0.0',
              urgency: NewFirmwareUrgency.security,
            ),
            phaseDuration: const Duration(milliseconds: 10),
          ),
        );
        expect(engine.stateReasons, contains(FwStateReason.newFirmwareAvailable));

        await engine.debugRunPipelineToCompletion();

        expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareAvailable)));
        for (final attribute in engine.newFirmwareStatusAttributes) {
          expect(
            attribute.value,
            isA<IppNoValue>(),
            reason: '${attribute.name} should be no-value after a successful install',
          );
        }
      },
    );

    test('firmware-update-in-progress spans every phase from Acquisition through Cleanup', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '8.8.8',
            urgency: NewFirmwareUrgency.feature,
          ),
          phaseDuration: const Duration(milliseconds: 20),
        ),
      );

      final pipelineDone = engine.debugRunPipelineToCompletion();

      // Sampled mid-run (not the first or last tick) — whichever specific
      // phase happens to be active, the overall marker must be present too.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateInProgress));
      expect(engine.currentPhase, isNotNull);

      await pipelineDone;
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateInProgress)));
    });

    test('Cleanup itself failing adds firmware-update-failure without -success', () async {
      engine.replaceConfig(
        SimulationConfig(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '9.0.0',
            urgency: NewFirmwareUrgency.bugfix,
          ),
          phaseOutcomes: const {
            FwPhase.acquisition: PhaseOutcome.succeed,
            FwPhase.validation: PhaseOutcome.succeed,
            FwPhase.installation: PhaseOutcome.succeed,
            FwPhase.activation: PhaseOutcome.succeed,
            FwPhase.cleanup: PhaseOutcome.fail,
            FwPhase.recovery: PhaseOutcome.succeed,
          },
          phaseDuration: const Duration(milliseconds: 10),
        ),
      );

      await engine.debugRunPipelineToCompletion();

      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateFailure));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateSuccess)));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateInProgress)));
      // Cleanup (deleting temp install files) failing is cosmetic — the
      // Firmware itself already activated successfully.
      expect(engine.currentFirmwareVersion, '9.0.0');
    });

    test(
      'a successful install does not resurface as newly-available on the next discovery',
      () async {
        engine.replaceConfig(
          SimulationConfig(
            firmwareAvailable: true,
            firmwareInfo: FirmwareInfo.simple(
              name: 'main-controller',
              stringVersion: '4.2.0',
              urgency: NewFirmwareUrgency.security,
            ),
            phaseDuration: const Duration(milliseconds: 10),
          ),
        );

        await engine.debugRunPipelineToCompletion();
        expect(engine.newFirmware, isNull);
        expect(engine.config.firmwareAvailable, isFalse);

        // Anything that re-runs discovery afterward — another
        // Simulation Control edit, or a real Check-For-New-Printer-Firmware
        // — must not "rediscover" the Firmware that was just installed.
        engine.updateConfig((c) => c.copyWith(discoveryDelay: const Duration(seconds: 1)));

        expect(engine.newFirmware, isNull);
        expect(engine.newFirmwareOutOfBandState, FwOutOfBandState.neverChecked);
        expect(engine.stateReasons, isNot(contains(FwStateReason.newFirmwareAvailable)));
      },
    );
  });
}
