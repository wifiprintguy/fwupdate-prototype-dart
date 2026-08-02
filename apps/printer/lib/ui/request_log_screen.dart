import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../printer_state.dart';
import '../transaction_log_entry.dart';

class RequestLogScreen extends StatelessWidget {
  const RequestLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PrinterEngine>();
    final log = engine.requestLog;

    if (log.isEmpty) {
      return const Center(child: Text('No requests received yet.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: engine.clearRequestLog,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear'),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: log.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _LogTile(entry: log[index]),
          ),
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final TransactionLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isSuccess = entry.response.isSuccessful;
    return ExpansionTile(
      leading: Icon(
        isSuccess ? Icons.check_circle_outline : Icons.error_outline,
        color: isSuccess ? Colors.green : Colors.red,
      ),
      title: Text('${entry.operationName}  →  ${entry.statusName}'),
      subtitle: Text('${entry.timestamp.toLocal()}  from ${entry.remoteAddress}'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Request', style: Theme.of(context).textTheme.labelLarge),
              SelectableText(entry.request.toString(), style: _monospace),
              const SizedBox(height: 12),
              Text('Response', style: Theme.of(context).textTheme.labelLarge),
              SelectableText(entry.response.toString(), style: _monospace),
            ],
          ),
        ),
      ],
    );
  }

  static const _monospace = TextStyle(fontFamily: 'monospace', fontSize: 12);
}
