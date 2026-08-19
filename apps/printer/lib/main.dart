import 'dart:io';

import 'package:discovery/discovery.dart';
import 'package:flutter/material.dart';
import 'package:ipp/ipp.dart';
import 'package:provider/provider.dart';

import 'printer_state.dart';
import 'ui/printer_home_screen.dart';
import 'ui/request_log_screen.dart';
import 'ui/simulation_control_screen.dart';

/// The address other devices on the LAN can actually use to reach this
/// process — `localhost` only works when the Client happens to be running
/// on the same machine, which defeats the point of a cross-device test
/// harness.
///
/// This deliberately reports a real LAN IP rather than guessing a
/// `<hostname>.local` mDNS name: on macOS, `Platform.localHostname` returns
/// the BSD hostname (`gethostname()`), which is not necessarily the
/// Bonjour "Local Hostname" actually registered for `.local` resolution —
/// System Settings lets those drift apart (confirmed: a fresh machine here
/// reported `Mac` from `hostname` but `Raza.local` was the name that
/// actually resolved). A real IP has no such ambiguity and works even if
/// the Client's OS has no mDNS resolver at all.
Future<String> _localNetworkAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.address.startsWith('169.254.')) {
          return address.address;
        }
      }
    }
  } on SocketException {
    // Fall through to the hostname-based guess below.
  }
  return Platform.localHostname;
}

/// The port this app tries first, so it's the same across runs (handy for
/// bookmarking `ipp://host:13631/ipp/print`, or the Client app's "Connect
/// manually" field) rather than a fresh ephemeral port every launch.
const int defaultPrinterPort = 13631;

/// How many ports past [defaultPrinterPort] to try before giving up.
const int _maxPortAttempts = 20;

/// Binds [server] to [defaultPrinterPort], or the next free port above it if
/// that one's taken (e.g. another instance of this app is already running).
Future<int> _bindServer(IppServer server) async {
  var port = defaultPrinterPort;
  for (var attempt = 1; attempt < _maxPortAttempts; attempt++) {
    try {
      return await server.start(port: port);
    } on SocketException {
      port++;
    }
  }
  // Final attempt: let any failure surface normally rather than swallowing
  // it silently after exhausting the fallback range.
  return server.start(port: port);
}

void main() {
  // Deliberately call runApp() immediately, before starting the IPP server
  // or the mDNS advertiser. Both of those are native, fallible calls (e.g.
  // blocked by macOS App Sandbox entitlements, a port already in use, or a
  // denied Local Network permission) — if either hangs or throws, the app
  // must still be able to show *something* rather than leaving the OS
  // window permanently blank with nothing painted into it.
  runApp(const PrinterApp());
}

class PrinterApp extends StatelessWidget {
  const PrinterApp({super.key});

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
      home: const PrinterStartup(),
    );
  }
}

/// Owns starting the [IppServer] and [PrinterAdvertiser], and shows a
/// loading or error state while/if that's in progress — see [main] for why
/// this can't happen before [runApp].
class PrinterStartup extends StatefulWidget {
  const PrinterStartup({super.key});

  @override
  State<PrinterStartup> createState() => _PrinterStartupState();
}

class _PrinterStartupState extends State<PrinterStartup> {
  late final PrinterEngine _engine;
  late Future<(String host, int port)> _startup;

  @override
  void initState() {
    super.initState();
    _engine = PrinterEngine();
    _startup = _start();
  }

  Future<(String, int)> _start() async {
    final server = IppServer(_engine.handleRequest, onOtherRequest: _engine.handleOtherRequest);
    _engine.server = server;
    final port = await _bindServer(server);
    final host = await _localNetworkAddress();
    _engine.configureServerAddress(host, port);

    final advertiser = PrinterAdvertiser();
    await advertiser.start(
      name: _engine.printerName,
      port: port,
      scenarioNote: 'FWUPDATE prototype printer',
    );
    return (host, port);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(String, int)>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupError(
            error: snapshot.error!,
            onRetry: () => setState(() => _startup = _start()),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Starting IPP server…'),
                ],
              ),
            ),
          );
        }
        final (host, port) = snapshot.data!;
        return ChangeNotifierProvider<PrinterEngine>.value(
          value: _engine,
          child: PrinterHomePage(host: host, port: port),
        );
      },
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                "Couldn't start the IPP server or mDNS advertiser.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$error\n\nOn macOS this is usually a missing App Sandbox network '
                'entitlement, or a denied Local Network permission — see BUILD.md.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class PrinterHomePage extends StatefulWidget {
  const PrinterHomePage({super.key, required this.host, required this.port});

  final String host;
  final int port;

  @override
  State<PrinterHomePage> createState() => _PrinterHomePageState();
}

class _PrinterHomePageState extends State<PrinterHomePage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final address = '${widget.host}:${widget.port}';
    final pages = [
      PrinterHomeScreen(address: address),
      SimulationControlScreen(onScenarioApplied: () => setState(() => _tabIndex = 0)),
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
