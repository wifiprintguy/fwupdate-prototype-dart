import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../client_event_log_entry.dart';
import '../printer_session.dart';

class EventLogScreen extends StatelessWidget {
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PrinterSession>();
    if (session.eventLog.isEmpty) {
      return const Center(child: Text('No requests sent yet.'));
    }
    return ListView.separated(
      itemCount: session.eventLog.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _LogTile(entry: session.eventLog[index]),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final ClientEventLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(
        entry.isError ? Icons.error_outline : Icons.check_circle_outline,
        color: entry.isError ? Colors.red : Colors.green,
      ),
      title: Text('${entry.label}  →  ${entry.outcomeSummary}'),
      subtitle: Text('${entry.timestamp.toLocal()}'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Request', style: Theme.of(context).textTheme.labelLarge),
              SelectableText(entry.request.toString(), style: _monospace),
              if (entry.response != null) ...[
                const SizedBox(height: 12),
                Text('Response', style: Theme.of(context).textTheme.labelLarge),
                SelectableText(entry.response.toString(), style: _monospace),
              ],
              if (entry.error != null) ...[
                const SizedBox(height: 12),
                Text('Error', style: Theme.of(context).textTheme.labelLarge),
                SelectableText('${entry.error}', style: _monospace),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const _monospace = TextStyle(fontFamily: 'monospace', fontSize: 12);
}
