import 'package:flutter_test/flutter_test.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:fwupdate_printer/printer_state.dart';
import 'package:fwupdate_printer/simulation_config.dart';
import 'package:ipp/ipp.dart';

/// A fast config for driving the state machine in tests: new Firmware is
/// available, phases take 10ms, and nothing waits on a notice period.
SimulationConfig _fastConfig({
  String stringVersion = '2.0.0',
  String name = 'main-controller',
  String? patch,
  Map<FwPhase, PhaseOutcome>? phaseOutcomes,
  Duration phaseDuration = const Duration(milliseconds: 10),
  Duration midUpdateOutage = Duration.zero,
  Duration outcomeRetention = const Duration(seconds: 60),
  bool stopsAcceptingJobs = true,
}) {
  return SimulationConfig(
    firmwareAvailable: true,
    firmwareInfo: FirmwareInfo.simple(
      name: name,
      stringVersion: stringVersion,
      urgency: NewFirmwareUrgency.security,
      patch: patch,
    ),
    phaseOutcomes: phaseOutcomes ?? const SimulationConfig().phaseOutcomes,
    phaseDuration: phaseDuration,
    noticeDuration: Duration.zero,
    outcomeRetention: outcomeRetention,
    midUpdateOutageDuringActivation: midUpdateOutage,
    stopsAcceptingJobsDuringUpdate: stopsAcceptingJobs,
  );
}

Map<FwPhase, PhaseOutcome> _outcomes(Map<FwPhase, PhaseOutcome> overrides) => {
  ...const SimulationConfig().phaseOutcomes,
  ...overrides,
};

void main() {
  group('FirmwareStateMachine (via PrinterEngine)', () {
    late PrinterEngine engine;

    setUp(() {
      engine = PrinterEngine();
    });

    tearDown(() => engine.dispose());

    test('a successful run ends in firmware-update-completed and bumps the version', () async {
      engine.replaceConfig(_fastConfig());
      // updateConfig/replaceConfig already ran a synchronous discovery pass.
      expect(engine.newFirmware, isNotNull);
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateAvailable));

      await engine.debugRunPipelineToCompletion();

      expect(engine.newFirmware, isNull);
      expect(engine.currentFirmwareVersion, '2.0.0');
      expect(engine.currentFirmwareNames, ['main-controller']);
      expect(engine.currentFirmwarePatches, ['none']);
      expect(engine.firmwareUpdateDateTime, isNotNull);
      expect(engine.printerState, 3);
      expect(engine.isAcceptingJobs, isTrue);
      expect(engine.currentPhase, isNull);
      expect(engine.stateReasons, {FwStateReason.firmwareUpdateCompleted});
    });

    test('a failed phase lists its -failed keyword, runs Recovery, and ends aborted', () async {
      engine.replaceConfig(
        _fastConfig(phaseOutcomes: _outcomes({FwPhase.installation: PhaseOutcome.fail})),
      );

      final done = engine.debugRunPipelineToCompletion();

      // Installation failed after ~3 phases; Recovery is now running.
      await _waitUntil(() => engine.stateReasons.contains(FwStateReason.firmwareUpdateAborting));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateInstallationFailed));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateProcessing));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateInstallation)));
      expect(engine.currentPhase, FwPhase.recovery);

      await done;

      expect(engine.currentFirmwareVersion, '1.0.0');
      expect(engine.firmwareUpdateDateTime, isNull, reason: 'nothing was installed');
      expect(engine.newFirmware, isNotNull, reason: 'firmware stays available for a retry');
      expect(engine.stateReasons, {
        FwStateReason.firmwareUpdateAvailable,
        FwStateReason.firmwareUpdateInstallationFailed,
        FwStateReason.firmwareUpdateAborted,
      });
      expect(engine.printerState, 3);
      expect(engine.isAcceptingJobs, isTrue);
    });

    test('each phase keyword replaces the one before it', () async {
      engine.replaceConfig(_fastConfig(phaseDuration: const Duration(milliseconds: 30)));

      final seen = <Set<String>>[];
      engine.addListener(() => seen.add(engine.stateReasons));
      await engine.debugRunPipelineToCompletion();

      const phaseKeywords = {
        FwStateReason.firmwareUpdateAcquisition,
        FwStateReason.firmwareUpdateValidation,
        FwStateReason.firmwareUpdateInstallation,
        FwStateReason.firmwareUpdateActivation,
      };
      for (final reasons in seen) {
        expect(
          reasons.intersection(phaseKeywords).length,
          lessThanOrEqualTo(1),
          reason: 'only one phase is active at a time: $reasons',
        );
      }
      final order = [
        for (final reasons in seen) ...reasons.intersection(phaseKeywords),
      ].fold<List<String>>([], (list, k) => list.isEmpty || list.last != k ? [...list, k] : list);
      expect(order, [
        FwStateReason.firmwareUpdateAcquisition,
        FwStateReason.firmwareUpdateValidation,
        FwStateReason.firmwareUpdateInstallation,
        FwStateReason.firmwareUpdateActivation,
      ]);
    });

    test('firmware-update-pending comes first, then processing spans every phase', () async {
      engine.replaceConfig(_fastConfig(phaseDuration: const Duration(milliseconds: 20)));

      final seen = <Set<String>>[];
      engine.addListener(() => seen.add(engine.stateReasons));
      await engine.debugRunPipelineToCompletion();

      expect(seen.first, contains(FwStateReason.firmwareUpdatePending));
      expect(seen.first, isNot(contains(FwStateReason.firmwareUpdateProcessing)));
      for (final reasons in seen) {
        if (reasons.any(FwPhaseReasons.byPhase.values.map((r) => r.active).contains)) {
          expect(reasons, contains(FwStateReason.firmwareUpdateProcessing));
          expect(reasons, isNot(contains(FwStateReason.firmwareUpdatePending)));
        }
      }
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateProcessing)));
    });

    test('a printer that keeps accepting jobs stays idle during the update', () async {
      engine.replaceConfig(_fastConfig(stopsAcceptingJobs: false));

      final states = <int>{};
      engine.addListener(() => states.add(engine.printerState));
      await engine.debugRunPipelineToCompletion();

      expect(states, {3});
    });

    test('a restart after Activation lists restarting and takes the server offline', () async {
      engine.replaceConfig(_fastConfig(midUpdateOutage: const Duration(milliseconds: 20)));

      final unreachable = <bool>[];
      final reasonsWhenOffline = <Set<String>>[];
      engine.debugOnUnreachableChanged = (value) {
        unreachable.add(value);
        if (value) reasonsWhenOffline.add(engine.stateReasons);
      };

      await engine.debugRunPipelineToCompletion();

      expect(unreachable, contains(true));
      expect(unreachable.last, isFalse);
      expect(reasonsWhenOffline.single, contains(FwStateReason.restarting));
      expect(
        reasonsWhenOffline.single,
        isNot(contains(FwStateReason.firmwareUpdateActivation)),
      );
      expect(engine.stateReasons, {FwStateReason.firmwareUpdateCompleted});
    });

    test('a hung Recovery stays at firmware-update-aborting', () async {
      engine.replaceConfig(
        _fastConfig(
          phaseOutcomes: _outcomes({
            FwPhase.validation: PhaseOutcome.fail,
            FwPhase.recovery: PhaseOutcome.hang,
          }),
        ),
      );

      await engine.debugRunPipelineToCompletion();

      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateAborting));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateValidationFailed));
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateProcessing));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateAborted)));
    });

    test('completed/aborted and -failed clear after outcomeRetention', () async {
      engine.replaceConfig(
        _fastConfig(
          phaseOutcomes: _outcomes({FwPhase.acquisition: PhaseOutcome.fail}),
          outcomeRetention: const Duration(milliseconds: 30),
        ),
      );

      await engine.debugRunPipelineToCompletion();
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateAborted));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(engine.stateReasons, {FwStateReason.firmwareUpdateAvailable});
    });

    test('starting a new update clears the previous result', () async {
      engine.replaceConfig(
        _fastConfig(phaseOutcomes: _outcomes({FwPhase.activation: PhaseOutcome.fail})),
      );
      await engine.debugRunPipelineToCompletion();
      expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateActivationFailed));

      engine.updateConfig((c) => c.copyWith(phaseOutcomes: _outcomes({})));
      final done = engine.debugRunPipelineToCompletion();
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateAborted)));
      expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateActivationFailed)));
      await done;
      expect(engine.stateReasons, {FwStateReason.firmwareUpdateCompleted});
    });

    test('resetToNeverChecked clears all new-firmware state', () async {
      engine.replaceConfig(_fastConfig());
      expect(engine.newFirmware, isNotNull);

      engine.resetToNeverChecked();

      expect(engine.newFirmware, isNull);
      expect(engine.newFirmwareOutOfBandState, FwOutOfBandState.neverChecked);
      expect(engine.checkDateTime, isNull);
      expect(engine.stateReasons, isEmpty);
    });

    test('a successful install carries over the new patches, not just the version', () async {
      engine.replaceConfig(
        _fastConfig(name: 'wifi-module', stringVersion: '3.1.4', patch: 'CVE-2026-41210'),
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
      engine.replaceConfig(_fastConfig(stringVersion: '5.5.5'));

      final names = engine.newFirmwareStatusAttributes.map((a) => a.name).toSet();
      expect(names, {
        FwStatusAttr.newFirmwareCheckDateTime,
        FwStatusAttr.newFirmwareInfoUri,
        FwStatusAttr.newFirmwareKOctets,
        FwStatusAttr.newFirmwareName,
        FwStatusAttr.newFirmwareOfflineTime,
        FwStatusAttr.newFirmwarePatches,
        FwStatusAttr.newFirmwareStringVersion,
        FwStatusAttr.newFirmwareUrgency,
        FwStatusAttr.newFirmwareVersion,
      });
      final offlineAttr = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareOfflineTime,
      );
      expect((offlineAttr.value as IppInteger).value, 0, reason: 'no restart configured');
      final checkDateTimeAttr = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareCheckDateTime,
      );
      expect(checkDateTimeAttr.value, isA<IppDateTime>());
      final nameAttr = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareName,
      );
      expect(nameAttr.values.map((v) => v.toString()), ['main-controller']);
    });

    test('printer-new-firmware-offline-time goes out-of-band with the rest of Table 1', () {
      engine.replaceConfig(const SimulationConfig(repositoryState: RepositoryState.unreachable));
      final unknown = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareOfflineTime,
      );
      expect(unknown.value, isA<IppUnknown>());

      engine.resetToNeverChecked();
      final noValue = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareOfflineTime,
      );
      expect(noValue.value, isA<IppNoValue>());
    });

    test('printer-new-firmware-offline-time reports the restart outage in seconds', () {
      engine.replaceConfig(_fastConfig(midUpdateOutage: const Duration(seconds: 15)));

      final offline = engine.newFirmwareStatusAttributes.firstWhere(
        (a) => a.name == FwStatusAttr.newFirmwareOfflineTime,
      );
      expect((offline.value as IppInteger).value, 15);
    });

    test(
      'a successful install clears firmware-update-available and every data attribute to '
      'no-value',
      () async {
        engine.replaceConfig(_fastConfig(stringVersion: '6.0.0'));
        expect(engine.stateReasons, contains(FwStateReason.firmwareUpdateAvailable));

        await engine.debugRunPipelineToCompletion();

        expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateAvailable)));
        for (final attribute in engine.newFirmwareStatusAttributes) {
          expect(
            attribute.value,
            isA<IppNoValue>(),
            reason: '${attribute.name} should be no-value after a successful install',
          );
        }
      },
    );

    test(
      'a successful install does not resurface as newly-available on the next discovery',
      () async {
        engine.replaceConfig(_fastConfig(stringVersion: '4.2.0'));

        await engine.debugRunPipelineToCompletion();
        expect(engine.newFirmware, isNull);
        expect(engine.config.firmwareAvailable, isFalse);

        // Anything that re-runs discovery afterward — another
        // Simulation Control edit, or a real Check-For-New-Printer-Firmware
        // — must not "rediscover" the Firmware that was just installed.
        engine.updateConfig((c) => c.copyWith(discoveryDelay: const Duration(seconds: 1)));

        expect(engine.newFirmware, isNull);
        expect(engine.newFirmwareOutOfBandState, FwOutOfBandState.neverChecked);
        expect(engine.stateReasons, isNot(contains(FwStateReason.firmwareUpdateAvailable)));
      },
    );
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
