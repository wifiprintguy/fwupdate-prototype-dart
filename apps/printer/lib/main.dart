import 'package:discovery/discovery.dart';
import 'package:flutter/material.dart';
import 'package:ipp/ipp.dart';
import 'package:provider/provider.dart';

import 'printer_state.dart';
import 'ui/printer_home_screen.dart';
import 'ui/request_log_screen.dart';
import 'ui/simulation_control_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = PrinterEngine();
  final server = IppServer(engine.handleRequest);
  engine.server = server;
  final port = await server.start();

  final advertiser = PrinterAdvertiser();
  await advertiser.start(
    name: engine.printerName,
    port: port,
    scenarioNote: 'FWUPDATE prototype printer',
  );

  runApp(
    ChangeNotifierProvider<PrinterEngine>.value(
      value: engine,
      child: PrinterApp(port: port),
    ),
  );
}

class PrinterApp extends StatelessWidget {
  const PrinterApp({super.key, required this.port});

  final int port;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FWUPDATE Printer Simulator',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: PrinterHomePage(port: port),
    );
  }
}

class PrinterHomePage extends StatefulWidget {
  const PrinterHomePage({super.key, required this.port});

  final int port;

  @override
  State<PrinterHomePage> createState() => _PrinterHomePageState();
}

class _PrinterHomePageState extends State<PrinterHomePage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final address = 'localhost:${widget.port}';
    final pages = [
      PrinterHomeScreen(address: address),
      const SimulationControlScreen(),
      const RequestLogScreen(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('FWUPDATE Printer Simulator')),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.print), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.bug_report), label: 'Simulate'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Log'),
        ],
      ),
    );
  }
}
