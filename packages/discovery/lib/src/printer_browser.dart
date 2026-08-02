import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'discovered_printer.dart';
import 'service_type.dart';

/// Browses for [ippServiceType] instances on the LAN and emits the current
/// set of resolved Printers every time it changes, so the Client app's
/// discovery screen can just render whatever the latest snapshot is.
class PrinterBrowser {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final _controller = StreamController<List<DiscoveredPrinter>>.broadcast();
  final Map<String, DiscoveredPrinter> _found = {};

  Stream<List<DiscoveredPrinter>> get printers => _controller.stream;

  Future<void> start() async {
    await stop();
    final discovery = BonsoirDiscovery(type: ippServiceType);
    await discovery.ready;
    _subscription = discovery.eventStream?.listen(_onEvent);
    await discovery.start();
    _discovery = discovery;
  }

  Future<void> _onEvent(BonsoirDiscoveryEvent event) async {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        final service = event.service;
        final discovery = _discovery;
        if (service != null && discovery != null) {
          await service.resolve(discovery.serviceResolver);
        }
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service;
        if (service is ResolvedBonsoirService && service.host != null) {
          _found[service.name] = DiscoveredPrinter(
            name: service.name,
            host: service.host!,
            port: service.port,
            attributes: service.attributes,
          );
          _emit();
        }
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final service = event.service;
        if (service != null && _found.remove(service.name) != null) {
          _emit();
        }
      default:
        break;
    }
  }

  void _emit() => _controller.add(_found.values.toList(growable: false));

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null && !discovery.isStopped) {
      await discovery.stop();
    }
    _found.clear();
  }

  void dispose() {
    unawaited(stop());
    _controller.close();
  }
}
