// Drives a real PrinterSession (this app) against a real PrinterEngine
// (the Printer app) over real HTTP on localhost — the cross-app version of
// the loopback idea in apps/printer/test/loopback_test.dart, proving the
// two apps' independently-developed IPP layers actually agree with each
// other on the wire, not just against their own package's fixtures.
import 'package:flutter_test/flutter_test.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:fwupdate_client/printer_session.dart';
import 'package:fwupdate_client/simulated_identity.dart';
import 'package:fwupdate_printer/printer_state.dart';
import 'package:fwupdate_printer/simulation_config.dart';
import 'package:ipp/ipp.dart';

void main() {
  late PrinterEngine engine;
  late IppServer server;
  late Uri printerUri;
  late SimulatedIdentity identity;
  late PrinterSession session;

  setUp(() async {
    engine = PrinterEngine();
    server = IppServer(engine.handleRequest);
    engine.server = server;
    final port = await server.start(port: 0);
    printerUri = Uri.parse('http://127.0.0.1:$port/ipp/print');
    identity = SimulatedIdentity();
    session = PrinterSession(
      printerUri: printerUri,
      identity: identity,
      pollInterval: const Duration(milliseconds: 30),
    );
  });

  tearDown(() async {
    session.dispose();
    await server.stop();
  });

  test('connect() populates attributes for a freshly-booted Printer', () async {
    await session.connect();
    expect(session.isConnected, isTrue);
    expect(session.printerState, 3);
    expect(session.isAcceptingJobs, isTrue);
    expect(session.newFirmware, isNull);
    expect(session.newFirmwareState, FwOutOfBandState.neverChecked);
  });

  test('checkForNewFirmware polls until the result is visible', () async {
    engine.updateConfig(
      (c) => c.copyWith(
        firmwareAvailable: true,
        firmwareInfo: FirmwareInfo.simple(
          name: 'main-controller',
          stringVersion: '9.9.0',
          urgency: NewFirmwareUrgency.feature,
        ),
        discoveryDelay: const Duration(milliseconds: 30),
      ),
    );
    engine.resetToNeverChecked();

    await session.connect();
    expect(session.newFirmware, isNull);

    await session.checkForNewFirmware();
    expect(session.isPolling, isTrue);

    await _waitUntil(() => session.newFirmware != null, timeout: const Duration(seconds: 2));

    expect(session.newFirmware!.stringVersions, ['9.9.0']);
    expect(session.stateReasons, contains(FwStateReason.newFirmwareAvailable));
  });

  test('requestUpdate drives a full install and the version bumps', () async {
    engine.updateConfig(
      (c) => c.copyWith(
        firmwareAvailable: true,
        firmwareInfo: FirmwareInfo.simple(
          name: 'main-controller',
          stringVersion: '9.9.1',
          urgency: NewFirmwareUrgency.bugfix,
        ),
        phaseDuration: const Duration(milliseconds: 10),
      ),
    );
    await session.connect();

    await session.requestUpdate();
    expect(session.isPolling, isTrue);

    await _waitUntil(
      () => session.currentFirmwareVersion == '9.9.1',
      timeout: const Duration(seconds: 2),
    );
    await _waitUntil(() => !session.isPolling, timeout: const Duration(seconds: 2));

    expect(session.newFirmware, isNull);
  });

  test('keeps polling (does not go fatal) through a mid-update outage', () async {
    engine.updateConfig(
      (c) => c.copyWith(
        firmwareAvailable: true,
        firmwareInfo: FirmwareInfo.simple(
          name: 'main-controller',
          stringVersion: '9.9.2',
          urgency: NewFirmwareUrgency.security,
        ),
        phaseDuration: const Duration(milliseconds: 10),
        midUpdateOutageDuringActivation: const Duration(milliseconds: 80),
      ),
    );
    await session.connect();

    await session.requestUpdate();

    await _waitUntil(
      () => session.currentFirmwareVersion == '9.9.2',
      timeout: const Duration(seconds: 3),
    );

    expect(session.isConnected, isTrue, reason: 'a transient outage must not leave isConnected false');
  });

  test('an unauthorized role is surfaced without crashing', () async {
    engine.updateConfig((c) => c.copyWith(authEnforcement: AuthEnforcement.byRole));
    identity.update(role: SimulatedRole.endUser);

    await session.checkForNewFirmware();

    expect(session.lastError, contains('client-error-not-authorized'));
  });
}

Future<void> _waitUntil(bool Function() condition, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
