import 'package:discovery/discovery.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../simulated_identity.dart';
import 'identity_screen.dart';
import 'printer_detail_screen.dart';

/// The Client app's home screen: browse for `_ipp._tcp` Printer-app
/// instances on the LAN (see package:discovery's [PrinterBrowser]) and tap
/// one to connect.
class DiscoveredPrintersScreen extends StatefulWidget {
  const DiscoveredPrintersScreen({super.key});

  @override
  State<DiscoveredPrintersScreen> createState() => _DiscoveredPrintersScreenState();
}

class _DiscoveredPrintersScreenState extends State<DiscoveredPrintersScreen> {
  final _browser = PrinterBrowser();
  List<DiscoveredPrinter> _printers = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _browser.printers.listen((printers) => setState(() => _printers = printers));
    _browser.start().catchError((Object e) => setState(() => _error = '$e'));
  }

  @override
  void dispose() {
    _browser.dispose();
    super.dispose();
  }

  Future<void> _connectManually() async {
    final controller = TextEditingController(text: 'localhost:');
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to a Printer'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'host:port'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (address == null || address.isEmpty || !mounted) return;
    final parts = address.split(':');
    if (parts.length != 2) return;
    final port = int.tryParse(parts[1]);
    if (port == null) return;
    _openPrinter(
      DiscoveredPrinter(name: address, host: parts[0], port: port, attributes: const {}),
    );
  }

  void _openPrinter(DiscoveredPrinter printer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PrinterDetailScreen(
          printerUri: printer.toPrinterUri(),
          displayName: printer.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FWUPDATE Client'),
        actions: [
          Consumer<SimulatedIdentity>(
            builder: (context, identity, _) => IconButton(
              icon: const Icon(Icons.badge_outlined),
              tooltip: 'Identity: ${identity.requestingUserName} (${identity.role.name})',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const IdentityScreen())),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
          : _printers.isEmpty
          ? const Center(child: Text('Searching for Printers on the LAN…'))
          : ListView.builder(
              itemCount: _printers.length,
              itemBuilder: (context, index) {
                final printer = _printers[index];
                return ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(printer.name),
                  subtitle: Text(
                    '${printer.host}:${printer.port}'
                    '${printer.scenarioNote != null ? ' · ${printer.scenarioNote}' : ''}',
                  ),
                  onTap: () => _openPrinter(printer),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _connectManually,
        icon: const Icon(Icons.add_link),
        label: const Text('Connect manually'),
      ),
    );
  }
}
