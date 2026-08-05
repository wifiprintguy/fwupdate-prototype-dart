import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ipp_constants.dart';
import 'ipp_message.dart';

/// Thrown when the HTTP layer itself fails or returns something other than
/// a 200 with an IPP body (e.g. a future TLS-upgrade-required response, or
/// a connection failure while the simulated Printer is "rebooting").
final class IppTransportException implements Exception {
  IppTransportException(this.message, {this.httpStatusCode, this.cause});

  final String message;
  final int? httpStatusCode;
  final Object? cause;

  @override
  String toString() => 'IppTransportException: $message'
      '${httpStatusCode != null ? ' (HTTP $httpStatusCode)' : ''}'
      '${cause != null ? ' caused by $cause' : ''}';
}

/// Sends an [IppMessage] as an HTTP POST and decodes the response body as
/// another [IppMessage]. This is deliberately independent of any specific
/// HTTP client instance lifecycle so callers (the Client app) can supply
/// per-request Basic Auth credentials to simulate different requesting
/// identities (see the Client app's Identity screen).
class IppClientTransport {
  IppClientTransport({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<IppMessage> send(
    Uri printerUri,
    IppMessage request, {
    String? basicAuthUsername,
    String? basicAuthPassword,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    late final HttpClientRequest httpRequest;
    try {
      httpRequest = await _httpClient
          .postUrl(_httpUriFor(printerUri))
          .timeout(timeout);
    } on Exception catch (e) {
      throw IppTransportException('Failed to connect to $printerUri', cause: e);
    }

    httpRequest.headers.set(HttpHeaders.contentTypeHeader, ippContentType);
    if (basicAuthUsername != null) {
      final credentials = base64Encode(
        utf8.encode('$basicAuthUsername:${basicAuthPassword ?? ''}'),
      );
      httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Basic $credentials');
    }
    httpRequest.add(request.encode());

    late final HttpClientResponse httpResponse;
    try {
      httpResponse = await httpRequest.close().timeout(timeout);
    } on Exception catch (e) {
      throw IppTransportException(
        'Connection to $printerUri failed or timed out — the Printer may '
        'be temporarily unreachable (e.g. mid-update reboot)',
        cause: e,
      );
    }

    late final List<int> bodyBytes;
    try {
      bodyBytes = await _readAll(httpResponse);
    } on Exception catch (e) {
      throw IppTransportException(
        'Connection to $printerUri was dropped while reading the response — '
        'the Printer may be temporarily unreachable (e.g. mid-update reboot)',
        cause: e,
      );
    }

    if (httpResponse.statusCode != HttpStatus.ok) {
      throw IppTransportException(
        'Unexpected HTTP status from $printerUri',
        httpStatusCode: httpResponse.statusCode,
      );
    }

    try {
      return IppMessage.decode(Uint8List.fromList(bodyBytes));
    } on FormatException catch (e) {
      throw IppTransportException(
        'Printer returned a malformed IPP response',
        cause: e,
      );
    }
  }

  /// IPP is HTTP underneath (RFC 8010) — `ipp`/`ipps` are just the URI
  /// scheme convention for "this is an IPP endpoint", not something
  /// `dart:io`'s [HttpClient] (or any real HTTP stack) understands as a
  /// connection scheme. Real IPP clients translate `ipp`→`http` and
  /// `ipps`→`https` before actually connecting, while still sending the
  /// original `ipp://` form as the `printer-uri` attribute *value* inside
  /// the request body — that translation belongs here (connection-level),
  /// not wherever `printerUri` was constructed.
  Uri _httpUriFor(Uri uri) => switch (uri.scheme) {
    'ipp' => uri.replace(scheme: 'http'),
    'ipps' => uri.replace(scheme: 'https'),
    _ => uri,
  };

  Future<List<int>> _readAll(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void close() => _httpClient.close(force: true);
}
