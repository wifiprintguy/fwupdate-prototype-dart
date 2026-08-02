import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../printer_session.dart';
import '../simulated_identity.dart';
import 'event_log_screen.dart';
import 'firmware_update_screen.dart';
import 'printer_attributes_screen.dart';

/// Hosts a [PrinterSession] for one connected Printer, across the
/// Attributes / Firmware Update / Event Log tabs.
class PrinterDetailScreen extends StatefulWidget {
  const PrinterDetailScreen({super.key, required this.printerUri, required this.displayName});

  final Uri printerUri;
  final String displayName;

  @override
  State<PrinterDetailScreen> createState() => _PrinterDetailScreenState();
}

class _PrinterDetailScreenState extends State<PrinterDetailScreen> {
  late final PrinterSession _session;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _session = PrinterSession(
      printerUri: widget.printerUri,
      identity: context.read<SimulatedIdentity>(),
      displayName: widget.displayName,
    );
    _session.connect();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PrinterSession>.value(
      value: _session,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.displayName)),
        body: const [
          PrinterAttributesScreen(),
          FirmwareUpdateScreen(),
          EventLogScreen(),
        ][_tabIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (i) => setState(() => _tabIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.info_outline), label: 'Attributes'),
            NavigationDestination(icon: Icon(Icons.system_update), label: 'Firmware'),
            NavigationDestination(icon: Icon(Icons.list_alt), label: 'Log'),
          ],
        ),
      ),
    );
  }
}
