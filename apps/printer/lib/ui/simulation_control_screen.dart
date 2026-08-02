import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:provider/provider.dart';

import '../printer_state.dart';
import '../scenario_presets.dart';
import '../simulation_config.dart';
import 'firmware_details_dialog.dart';

/// The fault-injection control panel: named one-tap presets, plus every
/// individual toggle from [SimulationConfig] for hand-tuning a scenario.
class SimulationControlScreen extends StatelessWidget {
  const SimulationControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PrinterEngine>();
    final config = engine.config;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Scenario presets', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...scenarioPresets.map(
          (preset) => Card(
            child: ListTile(
              title: Text(preset.name),
              subtitle: Text(preset.description),
              trailing: FilledButton(
                onPressed: () => preset.apply(engine),
                child: const Text('Apply'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Manual controls', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            title: const Text('Device clock is set'),
            subtitle: const Text(
              'Off ⇒ printer-new-firmware-check-date-time always reports unknown (§6.3.2)',
            ),
            value: engine.clockSet,
            onChanged: engine.setClockSet,
          ),
        ),
        _FirmwareAvailabilitySection(engine: engine, config: config),
        _RepositorySection(engine: engine, config: config),
        _PipelineSection(engine: engine, config: config),
        _AuthSection(engine: engine, config: config),
        _OperationsSection(engine: engine, config: config),
        _PolicySection(engine: engine, config: config),
        _DelaySection(engine: engine, config: config),
      ],
    );
  }
}

class _FirmwareAvailabilitySection extends StatelessWidget {
  const _FirmwareAvailabilitySection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  @override
  Widget build(BuildContext context) {
    final info = config.firmwareInfo;
    return Card(
      child: ExpansionTile(
        title: const Text('New firmware available'),
        initiallyExpanded: config.firmwareAvailable,
        children: [
          SwitchListTile(
            title: const Text('firmware-available'),
            value: config.firmwareAvailable,
            onChanged: (value) {
              engine.updateConfig(
                (c) => c.copyWith(
                  firmwareAvailable: value,
                  firmwareInfo: value && c.firmwareInfo == null
                      ? FirmwareInfo.simple(
                          name: 'main-controller',
                          stringVersion: '1.1.0',
                          urgency: NewFirmwareUrgency.feature,
                        )
                      : null,
                ),
              );
            },
          ),
          if (config.firmwareAvailable && info != null)
            ListTile(
              title: Text('${info.names.join(', ')}  v${info.stringVersions.join(', ')}'),
              subtitle: Text('urgency: ${info.urgency} · ${info.kOctets} kiB'),
              trailing: TextButton(
                onPressed: () async {
                  final updated = await showFirmwareDetailsDialog(context, initial: info);
                  if (updated != null) {
                    engine.updateConfig((c) => c.copyWith(firmwareInfo: updated));
                  }
                },
                child: const Text('Edit'),
              ),
            ),
        ],
      ),
    );
  }
}

class _RepositorySection extends StatelessWidget {
  const _RepositorySection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Firmware repository state'),
        subtitle: Text(config.repositoryState.name),
        children: RepositoryState.values
            .map(
              (state) => RadioListTile<RepositoryState>(
                title: Text(state.name),
                value: state,
                groupValue: config.repositoryState,
                onChanged: (value) =>
                    engine.updateConfig((c) => c.copyWith(repositoryState: value)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PipelineSection extends StatelessWidget {
  const _PipelineSection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  static const _phases = [
    FwPhase.acquisition,
    FwPhase.validation,
    FwPhase.installation,
    FwPhase.activation,
    FwPhase.cleanup,
    FwPhase.recovery,
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Install pipeline'),
        children: [
          for (final phase in _phases)
            ListTile(
              title: Text(phase.name),
              trailing: DropdownButton<PhaseOutcome>(
                value: config.phaseOutcomes[phase] ?? PhaseOutcome.succeed,
                items: PhaseOutcome.values
                    .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  engine.updateConfig(
                    (c) => c.copyWith(
                      phaseOutcomes: {...c.phaseOutcomes, phase: value},
                    ),
                  );
                },
              ),
            ),
          _DurationSlider(
            label: 'Phase duration',
            seconds: config.phaseDuration.inSeconds,
            min: 1,
            max: 30,
            onChanged: (s) =>
                engine.updateConfig((c) => c.copyWith(phaseDuration: Duration(seconds: s))),
          ),
          _DurationSlider(
            label: 'Discovery delay (Check-For-New-Printer-Firmware)',
            seconds: config.discoveryDelay.inSeconds,
            min: 0,
            max: 10,
            onChanged: (s) =>
                engine.updateConfig((c) => c.copyWith(discoveryDelay: Duration(seconds: s))),
          ),
          _DurationSlider(
            label: 'Mid-update outage during Activation (0 = disabled)',
            seconds: config.midUpdateOutageDuringActivation.inSeconds,
            min: 0,
            max: 30,
            onChanged: (s) => engine.updateConfig(
              (c) => c.copyWith(midUpdateOutageDuringActivation: Duration(seconds: s)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationSlider extends StatelessWidget {
  const _DurationSlider({
    required this.label,
    required this.seconds,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int seconds;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Slider(
        value: seconds.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: (max - min) == 0 ? null : max - min,
        label: '${seconds}s',
        onChanged: (v) => onChanged(v.round()),
      ),
      trailing: Text('${seconds}s'),
    );
  }
}

class _AuthSection extends StatelessWidget {
  const _AuthSection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Authorization (§5.1/§5.2)'),
        subtitle: Text(config.authEnforcement.name),
        children: AuthEnforcement.values
            .map(
              (mode) => RadioListTile<AuthEnforcement>(
                title: Text(_authLabel(mode)),
                value: mode,
                groupValue: config.authEnforcement,
                onChanged: (value) =>
                    engine.updateConfig((c) => c.copyWith(authEnforcement: value)),
              ),
            )
            .toList(),
      ),
    );
  }

  String _authLabel(AuthEnforcement mode) => switch (mode) {
    AuthEnforcement.off => 'off — allow any requester',
    AuthEnforcement.byRole =>
      'by role — reject unless Operator/Administrator (uses the status code for the sent role)',
    AuthEnforcement.forceForbidden => 'force forbidden — reject every request',
  };
}

class _OperationsSection extends StatelessWidget {
  const _OperationsSection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Operations supported'),
        children: [
          CheckboxListTile(
            title: const Text('Check-For-New-Printer-Firmware'),
            value: config.operations.checkForNewPrinterFirmware,
            onChanged: (value) => engine.updateConfig(
              (c) => c.copyWith(
                operations: c.operations.copyWith(checkForNewPrinterFirmware: value),
              ),
            ),
          ),
          CheckboxListTile(
            title: const Text('Update-Printer-Firmware'),
            value: config.operations.updatePrinterFirmware,
            onChanged: (value) => engine.updateConfig(
              (c) =>
                  c.copyWith(operations: c.operations.copyWith(updatePrinterFirmware: value)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text('printer-new-firmware-policy-configured'),
        subtitle: const Text(
          "Only 'auto' triggers autonomous install in this prototype (see README)",
        ),
        trailing: DropdownButton<String>(
          value: config.policy,
          items: NewFirmwarePolicy.all
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (value) {
            if (value != null) engine.updateConfig((c) => c.copyWith(policy: value));
          },
        ),
      ),
    );
  }
}

class _DelaySection extends StatelessWidget {
  const _DelaySection({required this.engine, required this.config});
  final PrinterEngine engine;
  final SimulationConfig config;

  static const _none = '(none — accept every delay-update-until value)';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text('Reject this delay-update-until value'),
        subtitle: const Text('Returned as unsupported (Group 3), per §5.2.1'),
        trailing: DropdownButton<String>(
          value: config.rejectedDelayUpdateUntilValue ?? _none,
          items: [
            const DropdownMenuItem(value: _none, child: Text(_none)),
            ...DelayUpdateUntil.all.map((v) => DropdownMenuItem(value: v, child: Text(v))),
          ],
          onChanged: (value) {
            engine.updateConfig(
              (c) => c.copyWith(
                rejectedDelayUpdateUntilValue: value == _none ? null : value,
                clearRejectedDelayUpdateUntilValue: value == _none,
              ),
            );
          },
        ),
      ),
    );
  }
}
