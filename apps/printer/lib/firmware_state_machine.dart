import 'package:fwupdate/fwupdate.dart';

import 'printer_state.dart';
import 'simulation_config.dart';

/// Runs a Firmware Update as drawn in Figure 7 of the spec, against a
/// [PrinterEngine], entirely driven by that engine's current
/// [SimulationConfig]:
///
/// ```text
/// Pending → Processing { Acquisition → Validation → Installation → Activation
///                         [→ Restarting] }                       → Completed
///         any phase fails → <phase>-failed → Aborting (Recovery)  → Aborted
/// ```
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
    bool superseded() => myRun != _runId;

    // Figure 7: an update is announced as Pending before Processing begins.
    engine.markPending();
    if (!await _wait(engine.config.noticeDuration, superseded)) return;
    engine.beginProcessing();

    FwPhase? failedPhase;
    for (final phase in FwPhaseReasons.pipeline) {
      final outcome = engine.config.phaseOutcomes[phase] ?? PhaseOutcome.succeed;
      engine.enterPhase(phase);
      if (outcome == PhaseOutcome.hang) return; // Stays in this phase until cancel()/reset.

      if (!await _wait(engine.config.phaseDuration, superseded)) return;

      if (outcome == PhaseOutcome.fail) {
        engine.failPhase(phase);
        failedPhase = phase;
        break;
      }
    }

    if (failedPhase != null) {
      // Recovery restores the previous Firmware. Figure 7 always ends it in
      // Aborted, so only `hang` changes its course.
      engine.enterPhase(FwPhase.recovery);
      final recoveryOutcome =
          engine.config.phaseOutcomes[FwPhase.recovery] ?? PhaseOutcome.succeed;
      if (recoveryOutcome == PhaseOutcome.hang) return;
      if (!await _wait(engine.config.phaseDuration, superseded)) return;
      _running = false;
      engine.concludeAborted();
      return;
    }

    // Figure 7: Activation → Printer Restarting → Completed, when the new
    // Firmware needs a reboot to take effect.
    final outage = engine.config.midUpdateOutageDuringActivation;
    if (outage > Duration.zero) {
      engine.announceRestart();
      if (!await _wait(engine.config.noticeDuration, superseded)) return;
      engine.beginOutage();
      if (!await _wait(outage, superseded)) return;
      engine.endOutage();
    }

    _running = false;
    engine.concludeCompleted();
  }

  /// Waits [duration] (skipping the timer entirely when it's zero) and
  /// returns whether this run is still current afterward.
  Future<bool> _wait(Duration duration, bool Function() superseded) async {
    if (duration > Duration.zero) await Future<void>.delayed(duration);
    return !superseded();
  }
}
