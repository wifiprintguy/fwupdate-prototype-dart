import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:provider/provider.dart';

import '../printer_state.dart';

class PrinterHomeScreen extends StatelessWidget {
  const PrinterHomeScreen({super.key, required this.address});

  final String address;

  static String printerStateLabel(int state) => switch (state) {
    3 => 'idle',
    4 => 'processing',
    5 => 'stopped',
    _ => 'unknown ($state)',
  };

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PrinterEngine>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(engine.printerName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                SelectableText('ipp://$address/ipp/print'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatusChip(label: printerStateLabel(engine.printerState)),
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: engine.isAcceptingJobs ? 'accepting jobs' : 'not accepting jobs',
                      color: engine.isAcceptingJobs ? Colors.green : Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'printer-state-reasons',
          child: engine.stateReasons.isEmpty
              ? const Text('none')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: engine.stateReasons.map((r) => _StatusChip(label: r)).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Currently installed Firmware',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('printer-firmware-string-version: ${engine.currentFirmwareVersion}'),
              if (engine.currentFirmwareInfoUri != null)
                Text('printer-firmware-info-uri: ${engine.currentFirmwareInfoUri}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'New Firmware status',
          child: _NewFirmwareSection(engine: engine),
        ),
        if (engine.currentPhase != null) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Install pipeline',
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Running: ${engine.currentPhase!.name}'),
              ],
            ),
          ),
        ],
        if (engine.delayedUntilKeyword != null || engine.delayedUntilDateTime != null) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Pending delayed install',
            child: Text(
              engine.delayedUntilKeyword != null
                  ? 'delay-update-until: ${engine.delayedUntilKeyword}'
                  : 'delay-update-until-date-time: ${engine.delayedUntilDateTime!.toLocal()}',
            ),
          ),
        ],
      ],
    );
  }
}

class _NewFirmwareSection extends StatelessWidget {
  const _NewFirmwareSection({required this.engine});

  final PrinterEngine engine;

  @override
  Widget build(BuildContext context) {
    final info = engine.newFirmware;
    if (info == null) {
      final state = engine.newFirmwareOutOfBandState;
      return Text(switch (state) {
        FwOutOfBandState.neverChecked => 'no-value (never checked / nothing available)',
        FwOutOfBandState.unknown => 'unknown (repository unreachable or errored)',
        FwOutOfBandState.none => 'no-value',
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('name: ${info.names.join(', ')}'),
        Text('string-version: ${info.stringVersions.join(', ')}'),
        Text('urgency: ${info.urgency}'),
        Text('k-octets: ${info.kOctets}'),
        Text('patches: ${info.patches.join(', ')}'),
        if (info.infoUri != null) Text('info-uri: ${info.infoUri}'),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color?.withValues(alpha: 0.15),
      side: color != null ? BorderSide(color: color!) : null,
    );
  }
}
