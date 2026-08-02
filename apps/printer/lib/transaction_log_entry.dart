import 'package:ipp/ipp.dart';

/// One recorded request/response pair, shown on the Request Log screen so a
/// discrepancy between "what the Client displayed" and "what the Printer
/// actually sent" is diagnosable immediately.
final class TransactionLogEntry {
  TransactionLogEntry({
    required this.timestamp,
    required this.remoteAddress,
    required this.request,
    required this.response,
  });

  final DateTime timestamp;
  final String remoteAddress;
  final IppMessage request;
  final IppMessage response;

  String get operationName => switch (request.operationId) {
    IppOperationId.getPrinterAttributes => 'Get-Printer-Attributes',
    IppOperationId.checkForNewPrinterFirmware => 'Check-For-New-Printer-Firmware',
    IppOperationId.updatePrinterFirmware => 'Update-Printer-Firmware',
    _ => '0x${request.operationId.toRadixString(16)}',
  };

  String get statusName => IppStatusCode.name(response.statusCode);
}
