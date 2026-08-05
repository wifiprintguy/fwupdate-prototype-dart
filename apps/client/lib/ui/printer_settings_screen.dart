import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:provider/provider.dart';

import '../printer_session.dart';
import '../simulated_identity.dart';

/// The "Settings" tab: identity/role (used for every request this Client
/// sends) and the automatic status-monitoring cadence, gathered in one
/// place away from the Status tab so that tab can stay focused on what's
/// actually happening on the Printer.
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _refreshSecondsController;
  late final TextEditingController _staleMinutesController;

  @override
  void initState() {
    super.initState();
    final identity = context.read<SimulatedIdentity>();
    final session = context.read<PrinterSession>();
    _nameController = TextEditingController(text: identity.requestingUserName);
    _refreshSecondsController = TextEditingController(
      text: '${session.statusMonitorInterval.inSeconds}',
    );
    _staleMinutesController = TextEditingController(
      text: '${session.autoCheckStaleThreshold.inMinutes}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _refreshSecondsController.dispose();
    _staleMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<SimulatedIdentity>();
    final session = context.watch<PrinterSession>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Identity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'This Client has no real login — pick a requesting-user-name and role, sent as '
          'HTTP Basic Auth, so the Printer\'s auth-enforcement simulation has something to '
          'check (FWUPDATE §5.1/§5.2).',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'requesting-user-name'),
          onChanged: (value) => identity.update(requestingUserName: value),
        ),
        const SizedBox(height: 12),
        Text('Role', style: Theme.of(context).textTheme.titleSmall),
        ...SimulatedRole.values.map(
          (role) => RadioListTile<SimulatedRole>(
            title: Text(_roleLabel(role)),
            value: role,
            groupValue: identity.role,
            onChanged: (value) => identity.update(role: value),
          ),
        ),
        const Divider(height: 32),
        Text('Status monitoring', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'This Client always keeps the Status tab fresh and automatically re-checks for new '
          "Firmware whenever the Printer has never checked (or can't say — no-value/unknown), "
          "or when its last check looks stale — these just tune how aggressively it does the "
          'latter.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _refreshSecondsController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Status refresh interval',
            suffixText: 'seconds',
          ),
          onSubmitted: (_) => _applyRefreshInterval(session),
          onChanged: (_) => _applyRefreshInterval(session),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _staleMinutesController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Also auto-check if the last check is older than',
            suffixText: 'minutes',
          ),
          onSubmitted: (_) => _applyStaleThreshold(session),
          onChanged: (_) => _applyStaleThreshold(session),
        ),
      ],
    );
  }

  void _applyRefreshInterval(PrinterSession session) {
    final seconds = int.tryParse(_refreshSecondsController.text.trim());
    if (seconds == null || seconds <= 0) return;
    session.setStatusMonitorInterval(Duration(seconds: seconds));
  }

  void _applyStaleThreshold(PrinterSession session) {
    final minutes = int.tryParse(_staleMinutesController.text.trim());
    if (minutes == null || minutes <= 0) return;
    session.setAutoCheckStaleThreshold(Duration(minutes: minutes));
  }

  String _roleLabel(SimulatedRole role) => switch (role) {
    SimulatedRole.administrator => 'Administrator (authorized)',
    SimulatedRole.operator => 'Operator (authorized)',
    SimulatedRole.endUser => 'End User (not authorized — expect client-error-not-authorized)',
    SimulatedRole.unauthenticated =>
      'Unauthenticated — sends no credentials at all (expect client-error-not-authenticated)',
  };
}
