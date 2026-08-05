import 'package:fwupdate/fwupdate.dart';

import 'printer_state.dart';
import 'simulation_config.dart';

/// Runs the install pipeline from Figure 1 of the spec (Acquisition →
/// Validation → Installation → Activation → [Recovery] → Cleanup) against a
/// [PrinterEngine], entirely driven by that engine's current
/// [SimulationConfig].
///
/// A monotonically increasing `_runId` lets a run be superseded (by
/// [cancel], or implicitly by starting a new run) without needing to tear
/// down in-flight `Future.delayed` timers — every `await` point re-checks
/// whether it's still the current run before touching engine state.
class FirmwareStateMachine {
  FirmwareStateMachine(this.engine);

  final PrinterEngine engine;
  int _runId = 0;
  bool _running = false;

  bool get isRunning => _running;

  /// Aborts the current run (if any) without resolving it one way or the
  /// other — used when the tester resets the scenario out from under an
  /// in-flight simulated update.
  void cancel() {
    _runId++;
    _running = false;
    engine.endOutage();
  }

  Future<void> run() async {
    final myRun = ++_runId;
    _running = true;
    engine.beginPipeline();

    const mainPhases = [
      FwPhase.acquisition,
      FwPhase.validation,
      FwPhase.installation,
      FwPhase.activation,
    ];

    var failed = false;
    for (final phase in mainPhases) {
      final outcome = engine.config.phaseOutcomes[phase] ?? PhaseOutcome.succeed;
      final reasons = FwPhaseReasons.byPhase[phase]!;
      engine.setPhaseInProgress(phase, reasons.inProgress);

      if (phase == FwPhase.activation &&
          engine.config.midUpdateOutageDuringActivation > Duration.zero) {
        engine.beginOutage();
        await Future.delayed(engine.config.midUpdateOutageDuringActivation);
        if (myRun != _runId) return;
        engine.endOutage();
      }

      if (outcome == PhaseOutcome.hang) {
        return; // Stays `-in-progress` until cancel()/reset.
      }

      await Future.delayed(engine.config.phaseDuration);
      if (myRun != _runId) return;

      if (outcome == PhaseOutcome.fail) {
        engine.setPhaseResult(phase, reasons.inProgress, reasons.failure, succeeded: false);
        failed = true;
        break;
      }
      engine.setPhaseResult(phase, reasons.inProgress, reasons.success, succeeded: true);
    }

    if (failed) {
      final recovered = await _runOnePhase(FwPhase.recovery, myRun);
      if (recovered == null) return; // hung or superseded
    }

    // Cleanup is handled inline rather than via [_runOnePhase]: its
    // completion is also the moment the whole pipeline is considered done,
    // so resolving it and concluding the pipeline must happen as one
    // atomic engine call — see [PrinterEngine.concludeAfterCleanup].
    final cleanupOutcome = engine.config.phaseOutcomes[FwPhase.cleanup] ?? PhaseOutcome.succeed;
    engine.setPhaseInProgress(FwPhase.cleanup, FwPhaseReasons.cleanup.inProgress);
    if (cleanupOutcome == PhaseOutcome.hang) return;

    await Future.delayed(engine.config.phaseDuration);
    if (myRun != _runId) return;

    _running = false;
    engine.concludeAfterCleanup(
      cleanupSucceeded: cleanupOutcome != PhaseOutcome.fail,
      installedSuccessfully: !failed,
    );
  }

  /// Runs the Recovery phase to completion (Cleanup is handled inline in
  /// [run] instead — see the comment there). Returns `true`/`false` for
  /// success/failure, or `null` if the phase hung or this run was
  /// superseded before it resolved.
  Future<bool?> _runOnePhase(FwPhase phase, int myRun) async {
    final outcome = engine.config.phaseOutcomes[phase] ?? PhaseOutcome.succeed;
    final reasons = FwPhaseReasons.byPhase[phase]!;
    engine.setPhaseInProgress(phase, reasons.inProgress);
    if (outcome == PhaseOutcome.hang) return null;

    await Future.delayed(engine.config.phaseDuration);
    if (myRun != _runId) return null;

    final succeeded = outcome != PhaseOutcome.fail;
    engine.setPhaseResult(
      phase,
      reasons.inProgress,
      succeeded ? reasons.success : reasons.failure,
      succeeded: succeeded,
    );
    return succeeded;
  }
}
