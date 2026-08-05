// Drives a real PrinterSession (this app) against a real PrinterEngine
// (the Printer app) over real HTTP on localhost — the cross-app version of
// the loopback idea in apps/printer/test/loopback_test.dart, proving the
// two apps' independently-developed IPP layers actually agree with each
// other on the wire, not just against their own package's fixtures.
//
// printerUri is built via DiscoveredPrinter.toPrinterUri() rather than a
// hand-written `http://` string — that's the real code path the Client app
// uses after mDNS discovery, and it produces an `ipp://` URI (per the IPP
// URI convention), not `http://`. An earlier version of this test used
// `Uri.parse('http://...')` directly, which meant it never actually
// exercised IppClientTransport's ipp/ipps-to-http/https scheme translation
// — masking a real bug where every genuine discovered-printer connection
// failed with "Unsupported scheme ipp".
import 'package:discovery/discovery.dart';
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
    printerUri = DiscoveredPrinter(
      name: 'Test Printer',
      host: '127.0.0.1',
      port: port,
      attributes: const {},
    ).toPrinterUri();
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

  // Also exercises PrinterSession's "grace poll" behavior: the Printer
  // advances check-date-time the instant it receives the request (see
  // PrinterEngine, §6.3.2), well before its delayed discovery result is
  // ready — so if the Client stopped polling as soon as check-date-time
  // merely changed, it would never see the firmware data land at all, and
  // this test would time out rather than fail with a clear assertion.
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

  group('status monitoring', () {
    // The persistent status monitor (statusMonitorInterval) always runs
    // once connected — there's no on/off switch to test, only that it
    // actually keeps attributes fresh and never flickers isBusy.
    test('picks up changes made independently of any check/update this session triggered', () async {
      final fastSession = PrinterSession(
        printerUri: printerUri,
        identity: identity,
        pollInterval: const Duration(milliseconds: 30),
        statusMonitorInterval: const Duration(milliseconds: 20),
      );
      addTearDown(fastSession.dispose);

      await fastSession.connect();
      expect(fastSession.currentFirmwareVersion, '1.0.0');

      // Simulates a change made directly on the Printer (e.g. via its own
      // Simulation Control screen), not through any request this session
      // sent — the only way to observe it is the status monitor.
      engine.setCurrentFirmwareVersion('2.5.0');

      await _waitUntil(
        () => fastSession.currentFirmwareVersion == '2.5.0',
        timeout: const Duration(seconds: 2),
      );
    });

    test('does not toggle isBusy on each tick', () async {
      final fastSession = PrinterSession(
        printerUri: printerUri,
        identity: identity,
        pollInterval: const Duration(milliseconds: 30),
        statusMonitorInterval: const Duration(milliseconds: 20),
      );
      addTearDown(fastSession.dispose);
      await fastSession.connect();

      final busyObserved = <bool>[];
      fastSession.addListener(() => busyObserved.add(fastSession.isBusy));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(busyObserved, isNot(contains(true)));
    });

    test('setStatusMonitorInterval takes effect immediately', () async {
      await session.connect();
      session.setStatusMonitorInterval(const Duration(milliseconds: 20));

      engine.setCurrentFirmwareVersion('3.0.0');

      await _waitUntil(
        () => session.currentFirmwareVersion == '3.0.0',
        timeout: const Duration(seconds: 2),
      );
    });
  });

  group('automatic Check-For-New-Printer-Firmware', () {
    bool sentAutomaticCheck(PrinterSession s) =>
        s.eventLog.any((e) => e.label == 'Check-For-New-Printer-Firmware');

    test('is sent on connect when check-date-time is no-value (never checked)', () async {
      engine.resetToNeverChecked();

      await session.connect();

      await _waitUntil(() => sentAutomaticCheck(session), timeout: const Duration(seconds: 2));
    });

    test('is not sent on connect when the Printer reports a recent check', () async {
      engine.checkDateTime = DateTime.now().toUtc();

      await session.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(sentAutomaticCheck(session), isFalse);
    });

    test('is sent when the last check is older than autoCheckStaleThreshold', () async {
      engine.checkDateTime = DateTime.now().toUtc().subtract(const Duration(milliseconds: 200));
      final staleSoonSession = PrinterSession(
        printerUri: printerUri,
        identity: identity,
        pollInterval: const Duration(milliseconds: 30),
        autoCheckStaleThreshold: const Duration(milliseconds: 50),
      );
      addTearDown(staleSoonSession.dispose);

      await staleSoonSession.connect();

      await _waitUntil(
        () => sentAutomaticCheck(staleSoonSession),
        timeout: const Duration(seconds: 2),
      );
    });
  });

  // printer-new-firmware-name's no-value is ambiguous on the wire between
  // "never checked" and "checked, nothing available" (FWUPDATE §6.3.5) —
  // isCheckingForFirmware is the Client's own record of an in-flight check,
  // so the UI can say "checking…" instead of showing that ambiguous
  // no-value while an automatic background check is quietly running.
  group('isCheckingForFirmware', () {
    test('reflects an automatic background check with no button press', () async {
      engine.resetToNeverChecked();

      await session.connect();
      expect(session.isCheckingForFirmware, isTrue);

      await _waitUntil(() => !session.isCheckingForFirmware, timeout: const Duration(seconds: 2));
    });

    test('reflects a manually-triggered check', () async {
      // A recent check-date-time so connect()'s own automatic check (see
      // the group above) doesn't fire and confound this assertion.
      engine.checkDateTime = DateTime.now().toUtc();

      await session.connect();
      expect(session.isCheckingForFirmware, isFalse);

      // printer-new-firmware-check-date-time only has decisecond (100ms)
      // resolution on the wire (see IppDateTime.fromDateTimeUtc) — without
      // this gap, this check could land in the same decisecond as the one
      // connect() just recorded, and the grace-poll logic (correctly) would
      // never see check-date-time change, so it would poll forever.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final checkFuture = session.checkForNewFirmware();
      expect(session.isCheckingForFirmware, isTrue);
      await checkFuture;

      await _waitUntil(() => !session.isCheckingForFirmware, timeout: const Duration(seconds: 2));
    });
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
