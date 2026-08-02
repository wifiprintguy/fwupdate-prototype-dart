import 'package:bonsoir/bonsoir.dart';

import 'service_type.dart';

/// Advertises this device as a FWUPDATE-capable IPP Printer over mDNS/
/// DNS-SD, so the Client app can find it on the LAN without the tester
/// typing in an address.
///
/// TXT record keys follow the IPP-over-Bonjour convention loosely (`rp`,
/// `ty`) plus a `note` key this project uses to surface the Printer's
/// currently active simulation scenario in the Client's discovery list
/// before it even connects.
class PrinterAdvertiser {
  BonsoirBroadcast? _broadcast;

  bool get isBroadcasting => _broadcast != null && !_broadcast!.isStopped;

  /// Starts (or restarts, if already running) advertising. Bonsoir has no
  /// API to update a running broadcast's TXT records, so changing the
  /// scenario note while already broadcasting stops and restarts under the
  /// hood.
  Future<void> start({
    required String name,
    required int port,
    required String scenarioNote,
  }) async {
    await stop();
    final service = BonsoirService(
      name: name,
      type: ippServiceType,
      port: port,
      attributes: {'txtvers': '1', 'rp': '', 'ty': name, 'note': scenarioNote},
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.ready;
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> stop() async {
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null && !broadcast.isStopped) {
      await broadcast.stop();
    }
  }
}
