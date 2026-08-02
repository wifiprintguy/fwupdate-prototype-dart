import 'package:fwupdate/fwupdate.dart';
import 'package:ipp/ipp.dart';
import 'package:test/test.dart';

void main() {
  group('operation request builders', () {
    test('buildUpdatePrinterFirmwareRequest rejects conflicting delay attrs', () {
      expect(
        () => buildUpdatePrinterFirmwareRequest(
          printerUri: 'ipp://printer.local:1631/ipp/print',
          requestId: 1,
          delayUpdateUntil: DelayUpdateUntil.evening,
          delayUpdateUntilDateTime: DateTime.utc(2026, 8, 2, 23),
        ),
        throwsA(isA<ConflictingDelayAttributesError>()),
      );
    });

    test('buildUpdatePrinterFirmwareRequest with a named delay round-trips', () {
      final request = buildUpdatePrinterFirmwareRequest(
        printerUri: 'ipp://printer.local:1631/ipp/print',
        requestId: 7,
        delayUpdateUntil: DelayUpdateUntil.night,
      );
      final decoded = IppMessage.decode(request.encode());
      expect(decoded.operationId, IppOperationId.updatePrinterFirmware);
      expect(
        decoded.operationAttributes[FwOperationAttr.delayUpdateUntil]!.value
            .toString(),
        DelayUpdateUntil.night,
      );
    });
  });

  group('FirmwareInfo', () {
    test('round-trips through IPP attributes', () {
      final info = FirmwareInfo.simple(
        name: 'main-controller',
        stringVersion: '2.4.1',
        urgency: NewFirmwareUrgency.security,
        infoUri: Uri.parse('https://example.com/release-notes/2.4.1'),
      );

      final message = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: info.toAttributes(),
      );
      final decoded = IppMessage.decode(message.encode());

      final parsed = FirmwareInfo.tryParse(decoded.printerAttributes);
      expect(parsed, isNotNull);
      expect(parsed!.names, ['main-controller']);
      expect(parsed.stringVersions, ['2.4.1']);
      expect(parsed.urgency, NewFirmwareUrgency.security);
      expect(parsed.infoUri, Uri.parse('https://example.com/release-notes/2.4.1'));
    });

    test('FwOutOfBandState.of distinguishes never-checked from unknown', () {
      final neverChecked = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: buildOutOfBandFirmwareDataAttributes(const IppNoValue()),
      );
      final unknown = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: buildOutOfBandFirmwareDataAttributes(const IppUnknown()),
      );

      final decodedNeverChecked = IppMessage.decode(neverChecked.encode());
      final decodedUnknown = IppMessage.decode(unknown.encode());

      expect(
        FwOutOfBandState.of(decodedNeverChecked.printerAttributes),
        FwOutOfBandState.neverChecked,
      );
      expect(
        FwOutOfBandState.of(decodedUnknown.printerAttributes),
        FwOutOfBandState.unknown,
      );
      expect(FirmwareInfo.tryParse(decodedNeverChecked.printerAttributes), isNull);
    });
  });

  group('SimulatedRole', () {
    test('only Administrator/Operator are authorized', () {
      expect(SimulatedRole.administrator.isAuthorizedForFirmwareOperations, isTrue);
      expect(SimulatedRole.operator.isAuthorizedForFirmwareOperations, isTrue);
      expect(SimulatedRole.endUser.isAuthorizedForFirmwareOperations, isFalse);
      expect(SimulatedRole.unauthenticated.isAuthorizedForFirmwareOperations, isFalse);
    });

    test('rejection codes match FWUPDATE §5.1/§5.2', () {
      expect(
        SimulatedRole.unauthenticated.rejectionStatusCode,
        IppStatusCode.clientErrorNotAuthenticated,
      );
      expect(
        SimulatedRole.endUser.rejectionStatusCode,
        IppStatusCode.clientErrorNotAuthorized,
      );
    });
  });
}
