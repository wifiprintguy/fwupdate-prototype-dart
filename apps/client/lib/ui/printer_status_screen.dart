import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:ipp/ipp.dart';
import 'package:provider/provider.dart';

import '../printer_session.dart';

enum _DelayChoice { immediate, namedKeyword, specificDateTime }

/// The "Status" tab: printer attributes plus the firmware check/update
/// controls in one screen, since watching the New Firmware status change in
/// response to those actions is the whole point — splitting them across
/// separate tabs just made that harder to see.
class PrinterStatusScreen extends StatefulWidget {
  const PrinterStatusScreen({super.key});

  @override
  State<PrinterStatusScreen> createState() => _PrinterStatusScreenState();
}

class _PrinterStatusScreenState extends State<PrinterStatusScreen> {
  _DelayChoice _delayChoice = _DelayChoice.immediate;
  String _delayKeyword = DelayUpdateUntil.evening;
  DateTime _delayDateTime = DateTime.now().add(const Duration(minutes: 1));
  late final TextEditingController _autoRefreshSecondsController;

  @override
  void initState() {
    super.initState();
    _autoRefreshSecondsController = TextEditingController(text: '10');
  }

  @override
  void dispose() {
    _autoRefreshSecondsController.dispose();
    super.dispose();
  }

  static String _printerStateLabel(int? state) => switch (state) {
    3 => 'idle',
    4 => 'processing',
    5 => 'stopped',
    null => 'unknown',
    _ => 'unknown ($state)',
  };

  void _applyAutoRefreshSeconds(PrinterSession session, {required bool enabled}) {
    final seconds = int.tryParse(_autoRefreshSecondsController.text.trim());
    if (seconds == null || seconds <= 0) return;
    session.setAutoRefreshEnabled(enabled, interval: Duration(seconds: seconds));
  }

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

    final checkSupported = session.supportsOperation(IppOperationId.checkForNewPrinterFirmware);
    final updateSupported = session.supportsOperation(IppOperationId.updatePrinterFirmware);

    return RefreshIndicator(
      onRefresh: session.refreshAttributes,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (session.lastError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(session.lastError!)),
            ),
          if (!checkSupported || !updateSupported)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  "This Printer's operations-supported does not list one or both FWUPDATE "
                  'operations — it may not implement this specification.',
                ),
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
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: session.isBusy || !checkSupported ? null : session.checkForNewFirmware,
              icon: const Icon(Icons.search),
              label: const Text('Check for new Firmware'),
            ),
          ),
          Row(
            children: [
              Switch(
                value: session.isAutoRefreshing,
                onChanged: (enabled) => _applyAutoRefreshSeconds(session, enabled: enabled),
              ),
              const Text('Auto-refresh every'),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: _autoRefreshSecondsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, suffixText: 's'),
                  onSubmitted: (_) =>
                      _applyAutoRefreshSeconds(session, enabled: session.isAutoRefreshing),
                  onChanged: (_) {
                    if (session.isAutoRefreshing) {
                      _applyAutoRefreshSeconds(session, enabled: true);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(title: 'New Firmware status', children: _newFirmwareLines(session)),
          _DelaySelector(
            choice: _delayChoice,
            keyword: _delayKeyword,
            dateTime: _delayDateTime,
            onChoiceChanged: (v) => setState(() => _delayChoice = v),
            onKeywordChanged: (v) => setState(() => _delayKeyword = v),
            onPickDateTime: () => _pickDateTime(context),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: session.isBusy || !updateSupported || session.newFirmware == null
                  ? null
                  : () => session.requestUpdate(
                      delayUpdateUntil: _delayChoice == _DelayChoice.namedKeyword
                          ? _delayKeyword
                          : null,
                      delayUpdateUntilDateTime: _delayChoice == _DelayChoice.specificDateTime
                          ? _delayDateTime
                          : null,
                    ),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Update Firmware'),
            ),
          ),
          if (session.newFirmware == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No new Firmware known to be available — check first, or the request will be '
                'a no-op.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 12),
          if (session.isPolling)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _progressSummary(session.stateReasons) ?? 'Waiting for progress…',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (session.delayedUntilKeyword != null || session.delayedUntilDateTime != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(
                  session.delayedUntilKeyword != null
                      ? 'Install delayed until: ${session.delayedUntilKeyword}'
                      : 'Install delayed until: ${session.delayedUntilDateTime!.toLocal()}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _delayDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_delayDateTime),
    );
    if (time == null) return;
    setState(() {
      _delayDateTime = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  List<Widget> _newFirmwareLines(PrinterSession session) {
    final info = session.newFirmware;
    if (info == null) {
      return [
        Text(
          switch (session.newFirmwareState) {
            FwOutOfBandState.neverChecked => 'no-value — never checked, or nothing available',
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

  String? _progressSummary(Set<String> reasons) {
    final inProgress = reasons.where((r) => r.endsWith('-in-progress'));
    if (inProgress.isEmpty) return null;
    return 'In progress: ${inProgress.join(', ')}';
  }
}

/// A compact "when to install" control: one dropdown for the top-level
/// choice, plus a second, narrower control that only appears for whichever
/// choice needs more detail — instead of three tall [RadioListTile]s.
class _DelaySelector extends StatelessWidget {
  const _DelaySelector({
    required this.choice,
    required this.keyword,
    required this.dateTime,
    required this.onChoiceChanged,
    required this.onKeywordChanged,
    required this.onPickDateTime,
  });

  final _DelayChoice choice;
  final String keyword;
  final DateTime dateTime;
  final ValueChanged<_DelayChoice> onChoiceChanged;
  final ValueChanged<String> onKeywordChanged;
  final VoidCallback onPickDateTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<_DelayChoice>(
          initialValue: choice,
          decoration: const InputDecoration(
            labelText: 'When to install',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: _DelayChoice.immediate, child: Text('Install immediately')),
            DropdownMenuItem(value: _DelayChoice.namedKeyword, child: Text('Delay until…')),
            DropdownMenuItem(value: _DelayChoice.specificDateTime, child: Text('Specific time…')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChoiceChanged(v);
            if (v == _DelayChoice.specificDateTime) onPickDateTime();
          },
        ),
        if (choice == _DelayChoice.namedKeyword)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<String>(
              initialValue: keyword,
              decoration: const InputDecoration(
                labelText: 'delay-update-until',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: DelayUpdateUntil.all
                  .where((k) => k != DelayUpdateUntil.noDelay)
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) => onKeywordChanged(v ?? keyword),
            ),
          ),
        if (choice == _DelayChoice.specificDateTime)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: onPickDateTime,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${dateTime.toLocal()}'),
            ),
          ),
      ],
    );
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
