import 'package:ipp/ipp.dart';
import 'package:test/test.dart';

void main() {
  group('IppMessage encode/decode round-trip', () {
    test('round-trips a request with common value types', () {
      final request = IppMessage.request(
        operationId: IppOperationId.checkForNewPrinterFirmware,
        requestId: 42,
        printerUri: 'ipp://printer.local:1631/ipp/print',
        requestingUserName: 'rafael',
      );

      final decoded = IppMessage.decode(request.encode());

      expect(decoded.operationId, IppOperationId.checkForNewPrinterFirmware);
      expect(decoded.requestId, 42);
      final op = decoded.operationAttributes;
      expect(op['attributes-charset']!.value, isA<IppCharset>());
      expect(op['printer-uri']!.value.toString(),
          'ipp://printer.local:1631/ipp/print');
      expect(op['requesting-user-name']!.value.toString(), 'rafael');
    });

    test('round-trips out-of-band values', () {
      final message = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: [
          IppAttribute.single('printer-new-firmware-version', const IppNoValue()),
          IppAttribute.single('printer-new-firmware-k-octets', const IppUnknown()),
        ],
      );

      final decoded = IppMessage.decode(message.encode());
      final attrs = decoded.printerAttributes;
      expect(attrs['printer-new-firmware-version']!.value, isA<IppNoValue>());
      expect(attrs['printer-new-firmware-k-octets']!.value, isA<IppUnknown>());
    });

    test('round-trips a multi-valued (1setOf) attribute', () {
      final message = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: [
          IppAttribute('printer-new-firmware-name', const [
            IppName('main-controller'),
            IppName('wifi-module'),
          ]),
        ],
      );

      final decoded = IppMessage.decode(message.encode());
      final values = decoded.printerAttributes['printer-new-firmware-name']!.values;
      expect(values, hasLength(2));
      expect(values[0].toString(), 'main-controller');
      expect(values[1].toString(), 'wifi-module');
    });

    test('round-trips a dateTime value preserving UTC instant', () {
      final now = DateTime.utc(2026, 8, 2, 14, 30, 5);
      final message = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: [
          IppAttribute.single(
            'printer-new-firmware-check-date-time',
            IppDateTime.fromDateTimeUtc(now),
          ),
        ],
      );

      final decoded = IppMessage.decode(message.encode());
      final value = decoded
              .printerAttributes['printer-new-firmware-check-date-time']!
              .value
          as IppDateTime;
      expect(value.toDateTimeUtc(), now);
    });

    test('round-trips an unsupported-attributes group', () {
      final message = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        unsupportedAttributes: [
          IppAttribute.single('delay-update-until', const IppUnsupported()),
        ],
      );

      final decoded = IppMessage.decode(message.encode());
      final group = decoded.group(IppDelimiterTag.unsupportedAttributes);
      expect(group, isNotNull);
      expect(group!['delay-update-until']!.value, isA<IppUnsupported>());
    });

    test('encodes booleans and integers correctly', () {
      final message = IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: 1,
        printerAttributes: [
          IppAttribute.single('printer-is-accepting-jobs', const IppBoolean(true)),
          IppAttribute.single('printer-new-firmware-k-octets', const IppInteger(45000)),
        ],
      );

      final decoded = IppMessage.decode(message.encode());
      expect(
        (decoded.printerAttributes['printer-is-accepting-jobs']!.value as IppBoolean)
            .value,
        isTrue,
      );
      expect(
        (decoded.printerAttributes['printer-new-firmware-k-octets']!.value
                as IppInteger)
            .value,
        45000,
      );
    });
  });
}
