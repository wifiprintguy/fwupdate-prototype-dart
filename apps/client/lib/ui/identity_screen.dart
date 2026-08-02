import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:provider/provider.dart';

import '../simulated_identity.dart';

/// Lets the tester pick the identity/role this Client claims to have — see
/// [SimulatedIdentity] for why this stands in for real authentication.
class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final identity = context.read<SimulatedIdentity>();
    _nameController = TextEditingController(text: identity.requestingUserName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<SimulatedIdentity>();

    return Scaffold(
      appBar: AppBar(title: const Text('Identity')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This Client has no real login — pick a requesting-user-name and role, sent as '
            'HTTP Basic Auth, so the Printer\'s auth-enforcement simulation has something to '
            'check (FWUPDATE §5.1/§5.2).',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'requesting-user-name'),
            onChanged: (value) => identity.update(requestingUserName: value),
          ),
          const SizedBox(height: 16),
          Text('Role', style: Theme.of(context).textTheme.titleMedium),
          ...SimulatedRole.values.map(
            (role) => RadioListTile<SimulatedRole>(
              title: Text(_label(role)),
              value: role,
              groupValue: identity.role,
              onChanged: (value) => identity.update(role: value),
            ),
          ),
        ],
      ),
    );
  }

  String _label(SimulatedRole role) => switch (role) {
    SimulatedRole.administrator => 'Administrator (authorized)',
    SimulatedRole.operator => 'Operator (authorized)',
    SimulatedRole.endUser => 'End User (not authorized — expect client-error-not-authorized)',
    SimulatedRole.unauthenticated =>
      'Unauthenticated — sends no credentials at all (expect client-error-not-authenticated)',
  };
}
