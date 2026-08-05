import 'package:flutter/material.dart';
import 'package:ipp/ipp.dart';
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _AttributeRow(
                name: 'printer-state',
                value: _StatusChip(label: printerStateLabel(engine.printerState)),
              ),
              const Divider(height: 1),
              _AttributeRow(
                name: 'printer-is-accepting-jobs',
                value: _StatusChip(
                  label: engine.isAcceptingJobs ? 'accepting jobs' : 'not accepting jobs',
                  color: engine.isAcceptingJobs ? Colors.green : Colors.orange,
                ),
              ),
            ],
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
              SelectableText('printer-firmware-name: ${engine.currentFirmwareNames.join(', ')}'),
              SelectableText(
                'printer-firmware-string-version: ${engine.currentFirmwareVersion}',
              ),
              SelectableText(
                'printer-firmware-patches: ${engine.currentFirmwarePatches.join(', ')}',
              ),
              SelectableText('printer-firmware-info-uri: ${engine.currentFirmwareInfoUri}'),
              const SizedBox(height: 4),
              Text(
                'Edit this from the Simulate tab.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
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

/// Renders every `printer-new-firmware-*` attribute (§6.3.2, §6.3.5-6.3.11)
/// individually and by its real IPP name, built directly from
/// [PrinterEngine.newFirmwareStatusAttributes] — the exact list a
/// Get-Printer-Attributes response would carry — so this can't drift from
/// what a real Client actually receives, and out-of-band values
/// (`no-value`/`unknown`) are visible per-attribute rather than folded into
/// one blanket message for the whole group.
class _NewFirmwareSection extends StatelessWidget {
  const _NewFirmwareSection({required this.engine});

  final PrinterEngine engine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attribute in engine.newFirmwareStatusAttributes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText('${attribute.name}: ${_formatAttributeValue(attribute)}'),
          ),
      ],
    );
  }

  static String _formatAttributeValue(IppAttribute attribute) {
    final value = attribute.value;
    if (value is IppNoValue) return 'no-value';
    if (value is IppUnknown) return 'unknown';
    if (value is IppDateTime) return value.toDateTimeUtc().toLocal().toString();
    return attribute.values.map((v) => v.toString()).join(', ');
  }
}

/// One IPP attribute name on the left, its value on the right — for
/// attributes worth showing individually rather than grouped into a
/// [_SectionCard] (e.g. because each has its own status-color chip).
class _AttributeRow extends StatelessWidget {
  const _AttributeRow({required this.name, required this.value});

  final String name;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(name), value],
      ),
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
