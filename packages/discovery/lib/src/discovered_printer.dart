/// A resolved Printer-app instance found on the LAN.
final class DiscoveredPrinter {
  const DiscoveredPrinter({
    required this.name,
    required this.host,
    required this.port,
    required this.attributes,
  });

  final String name;
  final String host;
  final int port;
  final Map<String, String> attributes;

  /// The active-scenario hint the Printer app publishes in its `note` TXT
  /// record, if any (see [PrinterAdvertiser]).
  String? get scenarioNote => attributes['note'];

  Uri toPrinterUri({String path = '/ipp/print'}) =>
      Uri(scheme: 'ipp', host: host, port: port, path: path);

  @override
  String toString() => '$name ($host:$port)';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPrinter &&
      other.name == name &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(name, host, port);
}
