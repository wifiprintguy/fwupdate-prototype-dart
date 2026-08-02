// Runs the real IPP wire codec and real HTTP transport end-to-end: a real
// [IppServer] wraps [PrinterEngine.handleRequest], and a real
// [IppClientTransport] sends requests to it over `localhost`, the same way
// the Client app would. This is the fast, CI-friendly stand-in for the
// two-device manual testing described in the project README — no bonsoir
// discovery involved, just the protocol layer both apps share.
import 'package:flutter_test/flutter_test.dart';
import 'package:fwupdate/fwupdate.dart';
import 'package:fwupdate_printer/printer_state.dart';
import 'package:fwupdate_printer/simulation_config.dart';
import 'package:ipp/ipp.dart';

void main() {
  late PrinterEngine engine;
  late IppServer server;
  late IppClientTransport client;
  late Uri printerUri;
  var nextRequestId = 1;

  setUp(() async {
    engine = PrinterEngine();
    server = IppServer(engine.handleRequest);
    engine.server = server;
    final port = await server.start(port: 0);
    printerUri = Uri.parse('http://127.0.0.1:$port/ipp/print');
    client = IppClientTransport();
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  Future<IppMessage> send(IppMessage request, {String? user, String? pass}) => client.send(
    printerUri,
    request,
    basicAuthUsername: user,
    basicAuthPassword: pass,
  );

  group('Get-Printer-Attributes', () {
    test('reports the baseline idle/accepting-jobs state', () async {
      final response = await send(
        buildGetPrinterAttributesRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(response.isSuccessful, isTrue);
      final attrs = response.printerAttributes;
      expect((attrs['printer-state']!.value as IppEnum).value, 3);
      expect((attrs['printer-is-accepting-jobs']!.value as IppBoolean).value, isTrue);
      expect(attrs[FwStatusAttr.newFirmwareName]!.value, isA<IppNoValue>());
    });
  });

  group('Check-For-New-Printer-Firmware', () {
    test('discovers available firmware after the discovery delay elapses', () async {
      // updateConfig() re-runs discovery synchronously (for the Simulation
      // Control UI's instant-feedback behavior), so reset back to
      // never-checked afterward to genuinely exercise the
      // Check-For-New-Printer-Firmware round trip below.
      engine.updateConfig(
        (c) => c.copyWith(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '3.0.0',
            urgency: NewFirmwareUrgency.security,
          ),
          discoveryDelay: const Duration(milliseconds: 20),
        ),
      );
      engine.resetToNeverChecked();

      final ackResponse = await send(
        buildCheckForNewPrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(ackResponse.isSuccessful, isTrue);
      // Immediate response reflects pre-check (never-checked) state.
      expect(
        ackResponse.printerAttributes[FwStatusAttr.newFirmwareCheckDateTime]!.value,
        isA<IppNoValue>(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      final followUp = await send(
        buildGetPrinterAttributesRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      final info = FirmwareInfo.tryParse(followUp.printerAttributes);
      expect(info, isNotNull);
      expect(info!.stringVersions, ['3.0.0']);
      expect(
        followUp.printerAttributes['printer-state-reasons']!.values
            .map((v) => v.toString()),
        contains(FwStateReason.newFirmwareAvailable),
      );
    });

    test('reports firmware-repository-unreachable when configured', () async {
      engine.updateConfig(
        (c) => c.copyWith(
          repositoryState: RepositoryState.unreachable,
          discoveryDelay: Duration.zero,
        ),
      );

      await send(
        buildCheckForNewPrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final response = await send(
        buildGetPrinterAttributesRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(
        response.printerAttributes['printer-state-reasons']!.values
            .map((v) => v.toString()),
        contains(FwStateReason.firmwareRepositoryUnreachable),
      );
      expect(response.printerAttributes[FwStatusAttr.newFirmwareName]!.value, isA<IppUnknown>());
    });
  });

  group('Update-Printer-Firmware', () {
    setUp(() {
      engine.updateConfig(
        (c) => c.copyWith(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '4.0.0',
            urgency: NewFirmwareUrgency.bugfix,
          ),
          phaseDuration: const Duration(milliseconds: 10),
        ),
      );
    });

    test('rejects conflicting delay attributes', () async {
      final request = IppMessage.request(
        operationId: IppOperationId.updatePrinterFirmware,
        requestId: nextRequestId++,
        printerUri: printerUri.toString(),
        operationAttributes: [
          IppAttribute.single(FwOperationAttr.delayUpdateUntil, const IppKeyword('night')),
          IppAttribute.single(
            FwOperationAttr.delayUpdateUntilDateTime,
            IppDateTime.fromDateTimeUtc(DateTime.now().toUtc()),
          ),
        ],
      );
      final response = await send(request);
      expect(response.statusCode, IppStatusCode.clientErrorConflictingAttributes);
    });

    test('installs immediately with no-delay and eventually clears new-firmware attrs', () async {
      final response = await send(
        buildUpdatePrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(response.isSuccessful, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final attrs = await send(
        buildGetPrinterAttributesRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(attrs.printerAttributes['printer-firmware-string-version']!.value.toString(), '4.0.0');
      expect(attrs.printerAttributes[FwStatusAttr.newFirmwareName]!.value, isA<IppNoValue>());
    });

    test('rejects an unsupported delay-update-until value', () async {
      engine.updateConfig(
        (c) => c.copyWith(rejectedDelayUpdateUntilValue: DelayUpdateUntil.weekend),
      );
      final response = await send(
        buildUpdatePrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
          delayUpdateUntil: DelayUpdateUntil.weekend,
        ),
      );
      expect(response.statusCode, IppStatusCode.successfulOkIgnoredOrSubstitutedAttributes);
      final unsupported = response.group(IppDelimiterTag.unsupportedAttributes);
      expect(unsupported?[FwOperationAttr.delayUpdateUntil]?.value, isA<IppUnsupported>());
    });
  });

  group('Authorization', () {
    setUp(() {
      engine.updateConfig(
        (c) => c.copyWith(authEnforcement: AuthEnforcement.byRole),
      );
    });

    test('unauthenticated requester is rejected with client-error-not-authenticated', () async {
      final response = await send(
        buildCheckForNewPrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(response.statusCode, IppStatusCode.clientErrorNotAuthenticated);
    });

    test('end-user requester is rejected with client-error-not-authorized', () async {
      final response = await send(
        buildCheckForNewPrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
        user: 'rafael',
        pass: 'end-user',
      );
      expect(response.statusCode, IppStatusCode.clientErrorNotAuthorized);
    });

    test('operator requester is allowed', () async {
      final response = await send(
        buildCheckForNewPrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
        user: 'admin',
        pass: 'operator',
      );
      expect(response.isSuccessful, isTrue);
    });
  });

  group('Operation availability', () {
    test('server-error-operation-not-supported when disabled', () async {
      engine.updateConfig(
        (c) => c.copyWith(
          operations: const OperationAvailability(updatePrinterFirmware: false),
        ),
      );
      final response = await send(
        buildUpdatePrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(response.statusCode, IppStatusCode.serverErrorOperationNotSupported);
    });
  });

  group('Mid-update outage', () {
    test('the server drops connections while unreachable is simulated', () async {
      engine.updateConfig(
        (c) => c.copyWith(
          firmwareAvailable: true,
          firmwareInfo: FirmwareInfo.simple(
            name: 'main-controller',
            stringVersion: '5.0.0',
            urgency: NewFirmwareUrgency.bugfix,
          ),
          midUpdateOutageDuringActivation: const Duration(milliseconds: 100),
          phaseDuration: const Duration(milliseconds: 10),
        ),
      );

      await send(
        buildUpdatePrinterFirmwareRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );

      // Poll until the outage kicks in (Acquisition + Validation +
      // Installation each take ~10ms before Activation's outage begins).
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await expectLater(
        send(
          buildGetPrinterAttributesRequest(
            printerUri: printerUri.toString(),
            requestId: nextRequestId++,
          ),
        ),
        throwsA(isA<IppTransportException>()),
      );

      // And it recovers afterward.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final response = await send(
        buildGetPrinterAttributesRequest(
          printerUri: printerUri.toString(),
          requestId: nextRequestId++,
        ),
      );
      expect(response.isSuccessful, isTrue);
    });
  });
}
