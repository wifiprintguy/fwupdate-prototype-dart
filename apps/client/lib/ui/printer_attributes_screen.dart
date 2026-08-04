import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:provider/provider.dart';

import '../printer_session.dart';

class PrinterAttributesScreen extends StatelessWidget {
  const PrinterAttributesScreen({super.key});

  static String _printerStateLabel(int? state) => switch (state) {
    3 => 'idle',
    4 => 'processing',
    5 => 'stopped',
    null => 'unknown',
    _ => 'unknown ($state)',
  };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PrinterSession>();

    if (!session.hasAttributes && session.isBusy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!session.hasAttributes && session.lastError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Could not connect: ${session.lastError}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: session.refreshAttributes, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: session.refreshAttributes,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (session.lastError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(session.lastError!),
              ),
            ),
          _SectionCard(
            title: 'Printer status',
            children: [
              Text('printer-state: ${_printerStateLabel(session.printerState)}'),
              Text('printer-is-accepting-jobs: ${session.isAcceptingJobs}'),
            ],
          ),
          _SectionCard(
            title: 'printer-state-reasons',
            children: session.stateReasons.isEmpty
                ? [const Text('none')]
                : [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: session.stateReasons.map((r) => Chip(label: Text(r))).toList(),
                    ),
                  ],
          ),
          _SectionCard(
            title: 'Currently installed Firmware',
            children: [
              Text('printer-firmware-name: ${session.currentFirmwareNames.join(', ')}'),
              Text('printer-firmware-string-version: ${session.currentFirmwareVersion ?? '—'}'),
              Text('printer-firmware-patches: ${session.currentFirmwarePatches.join(', ')}'),
              if (session.currentFirmwareInfoUri != null)
                InkWell(
                  onTap: () {}, // A real Client would launch this URI; out of scope here.
                  child: Text(
                    'printer-firmware-info-uri: ${session.currentFirmwareInfoUri}',
                    style: const TextStyle(decoration: TextDecoration.underline),
                  ),
                ),
            ],
          ),
          _SectionCard(title: 'New Firmware status', children: _newFirmwareLines(session)),
        ],
      ),
    );
  }

  List<Widget> _newFirmwareLines(PrinterSession session) {
    final info = session.newFirmware;
    if (info == null) {
      return [
        Text(
          switch (session.newFirmwareState) {
            FwOutOfBandState.neverChecked =>
              'no-value — never checked, or nothing available',
            FwOutOfBandState.unknown => 'unknown — repository unreachable or errored',
            FwOutOfBandState.none => 'no-value',
          },
        ),
      ];
    }
    return [
      Text('name: ${info.names.join(', ')}'),
      Text('string-version: ${info.stringVersions.join(', ')}'),
      Text('urgency: ${info.urgency}'),
      Text('k-octets: ${info.kOctets}'),
      Text('patches: ${info.patches.join(', ')}'),
      if (info.infoUri != null) Text('info-uri: ${info.infoUri}'),
    ];
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
