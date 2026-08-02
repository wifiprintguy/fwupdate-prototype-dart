import 'package:ipp/ipp.dart';

/// One request this Client app made, and either the response it got back
/// or the transport error it hit — shown on the Event Log screen so a
/// discrepancy between "what the UI displayed" and "what actually happened
/// on the wire" is diagnosable immediately.
final class ClientEventLogEntry {
  ClientEventLogEntry({
    required this.timestamp,
    required this.label,
    required this.request,
    this.response,
    this.error,
  });

  final DateTime timestamp;
  final String label;
  final IppMessage request;
  final IppMessage? response;
  final Object? error;

  bool get isError => error != null || (response != null && !response!.isSuccessful);

  String get outcomeSummary {
    if (error != null) return 'transport error: $error';
    if (response != null) return IppStatusCode.name(response!.statusCode);
    return 'unknown';
  }
}
