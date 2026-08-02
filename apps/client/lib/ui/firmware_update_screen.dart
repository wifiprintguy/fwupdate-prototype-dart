import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:ipp/ipp.dart';
import 'package:provider/provider.dart';

import '../printer_session.dart';

enum _DelayChoice { immediate, namedKeyword, specificDateTime }

class FirmwareUpdateScreen extends StatefulWidget {
  const FirmwareUpdateScreen({super.key});

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateScreenState();
}

class _FirmwareUpdateScreenState extends State<FirmwareUpdateScreen> {
  _DelayChoice _delayChoice = _DelayChoice.immediate;
  String _delayKeyword = DelayUpdateUntil.evening;
  DateTime _delayDateTime = DateTime.now().add(const Duration(minutes: 1));

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PrinterSession>();

    final checkSupported = session.supportsOperation(
      IppOperationId.checkForNewPrinterFirmware,
    );
    final updateSupported = session.supportsOperation(IppOperationId.updatePrinterFirmware);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        FilledButton.icon(
          onPressed: session.isBusy || !checkSupported ? null : session.checkForNewFirmware,
          icon: const Icon(Icons.search),
          label: const Text('Check for new Firmware'),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Schedule install', style: Theme.of(context).textTheme.titleMedium),
                RadioListTile<_DelayChoice>(
                  title: const Text('Install immediately'),
                  value: _DelayChoice.immediate,
                  groupValue: _delayChoice,
                  onChanged: (v) => setState(() => _delayChoice = v!),
                ),
                RadioListTile<_DelayChoice>(
                  title: const Text('Delay until…'),
                  value: _DelayChoice.namedKeyword,
                  groupValue: _delayChoice,
                  onChanged: (v) => setState(() => _delayChoice = v!),
                ),
                if (_delayChoice == _DelayChoice.namedKeyword)
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: DropdownButton<String>(
                      value: _delayKeyword,
                      items: DelayUpdateUntil.all
                          .where((k) => k != DelayUpdateUntil.noDelay)
                          .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (v) => setState(() => _delayKeyword = v ?? _delayKeyword),
                    ),
                  ),
                RadioListTile<_DelayChoice>(
                  title: Text('Specific time: ${_delayDateTime.toLocal()}'),
                  value: _DelayChoice.specificDateTime,
                  groupValue: _delayChoice,
                  onChanged: (v) async {
                    setState(() => _delayChoice = v!);
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
                      _delayDateTime = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
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
          label: const Text('Request Update-Printer-Firmware'),
        ),
        if (session.newFirmware == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'No new Firmware known to be available — check first, or the request will be a '
              'no-op.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 24),
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
        if (session.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              session.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  String? _progressSummary(Set<String> reasons) {
    final inProgress = reasons.where((r) => r.endsWith('-in-progress'));
    if (inProgress.isEmpty) return null;
    return 'In progress: ${inProgress.join(', ')}';
  }
}
