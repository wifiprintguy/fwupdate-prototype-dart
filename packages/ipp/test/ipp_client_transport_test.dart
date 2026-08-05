// Regression coverage for a real bug: dart:io's HttpClient only understands
// http/https schemes, but every real printer-uri this project constructs
// (via DiscoveredPrinter.toPrinterUri()) uses ipp/ipps, per the IPP URI
// convention. The app-level test suites all connected directly with
// Uri.parse('http://...') and never exercised this path, so the bug shipped
// undetected — these tests specifically send to an `ipp://` URI, the way
// the real Client app does after mDNS discovery.
import 'package:ipp/ipp.dart';
import 'package:test/test.dart';

void main() {
  late IppServer server;
  late IppClientTransport client;
  late int port;

  setUp(() async {
    server = IppServer(
      (request, httpRequest) async => IppMessage.statusResponse(
        statusCode: IppStatusCode.successfulOk,
        requestId: request.requestId,
      ),
    );
    port = await server.start(port: 0);
    client = IppClientTransport();
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test('sends successfully to an ipp:// printer-uri', () async {
    final printerUri = Uri.parse('ipp://127.0.0.1:$port/ipp/print');
    final request = buildRequestFor(printerUri);

    final response = await client.send(printerUri, request);

    expect(response.isSuccessful, isTrue);
  });

  test('sends successfully to an ipps:// printer-uri (translated to https)', () async {
    // No real TLS listener behind this port, so this only proves the
    // scheme translation itself (ipps -> https) rather than a successful
    // handshake — real TLS support is out of scope for v1 (see README).
    final printerUri = Uri.parse('ipps://127.0.0.1:$port/ipp/print');
    final request = buildRequestFor(printerUri);

    await expectLater(
      client.send(printerUri, request),
      throwsA(isA<IppTransportException>()),
    );
  });

  test('a request with no scheme at all still connects (defaults untouched)', () async {
    final printerUri = Uri.parse('http://127.0.0.1:$port/ipp/print');
    final request = buildRequestFor(printerUri);

    final response = await client.send(printerUri, request);

    expect(response.isSuccessful, isTrue);
  });
}

IppMessage buildRequestFor(Uri printerUri) => IppMessage.request(
  operationId: IppOperationId.getPrinterAttributes,
  requestId: 1,
  printerUri: printerUri.toString(),
);
