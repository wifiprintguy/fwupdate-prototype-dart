import 'dart:io';
import 'dart:typed_data';

import 'ipp_constants.dart';
import 'ipp_message.dart';

/// A minimal HTTP/1.1 listener that decodes each POST body as an
/// [IppMessage], hands it to [handler], and writes back whatever
/// [IppMessage] the handler returns.
///
/// [setSimulateUnreachable] lets the Printer app simulate going dark for a
/// while (e.g. "rebooting" during the Activation phase, per FWUPDATE
/// §4.4/§5.2's explicit note that this can happen): while enabled, incoming
/// connections are aborted at the socket level instead of receiving any
/// HTTP response, which is what a Client actually observes when a real
/// printer drops off the network mid-update.
class IppServer {
  IppServer(this._handler, {Future<void> Function(HttpRequest request)? onOtherRequest})
    : _onOtherRequest = onOtherRequest;

  final Future<IppMessage> Function(IppMessage request, HttpRequest httpRequest)
  _handler;

  /// Handles any request that isn't a POST (i.e. not an IPP operation) —
  /// e.g. so the Printer app can serve real content at the URLs its
  /// `*-info-uri` attributes point to, instead of those being dead links.
  /// Requests are answered 404 if this is left unset.
  final Future<void> Function(HttpRequest request)? _onOtherRequest;

  HttpServer? _server;
  bool _simulateUnreachable = false;

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<int> start({int port = 0, InternetAddress? address}) async {
    final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handleRequest, onError: (Object _) {});
    return server.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_simulateUnreachable) {
      try {
        final socket = await request.response.detachSocket();
        socket.destroy();
      } catch (_) {
        // Best-effort: the point is just to not send a well-formed
        // response back.
      }
      return;
    }

    if (request.method != 'POST') {
      if (_onOtherRequest != null) {
        await _onOtherRequest(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
      return;
    }

    try {
      final bytes = await _readAll(request);
      final ippRequest = IppMessage.decode(bytes);
      final ippResponse = await _handler(ippRequest, request);
      request.response
        ..headers.set(HttpHeaders.contentTypeHeader, ippContentType)
        ..add(ippResponse.encode());
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<Uint8List> _readAll(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  void setSimulateUnreachable(bool value) {
    _simulateUnreachable = value;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
