import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'simulated_identity.dart';
import 'ui/discovered_printers_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider<SimulatedIdentity>(
      create: (_) => SimulatedIdentity(),
      child: const ClientApp(),
    ),
  );
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FWUPDATE Client',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const DiscoveredPrintersScreen(),
    );
  }
}
