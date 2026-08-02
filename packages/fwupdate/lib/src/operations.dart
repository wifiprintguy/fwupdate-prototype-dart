import 'package:ipp/ipp.dart';

import 'attributes.dart';

/// Thrown by [buildUpdatePrinterFirmwareRequest] if the caller tries to
/// supply both delay operation attributes — FWUPDATE §4.4 states a Client
/// "MUST NOT supply both". This is a client-side guard so the Client app
/// under test can't accidentally send a non-conformant request through this
/// builder; the Printer app's dispatcher enforces the same rule
/// independently (returning `client-error-conflicting-attributes`) since a
/// hand-built or "chaos mode" request could bypass this builder entirely.
final class ConflictingDelayAttributesError extends ArgumentError {
  ConflictingDelayAttributesError()
    : super(
        'delay-update-until and delay-update-until-date-time are mutually '
        'exclusive (FWUPDATE §4.4)',
      );
}

/// Builds a Get-Printer-Attributes request (baseline STD92/RFC 8011
/// operation; every Client interaction starts or checks in with this).
IppMessage buildGetPrinterAttributesRequest({
  required String printerUri,
  required int requestId,
  String requestingUserName = '',
}) {
  return IppMessage.request(
    operationId: IppOperationId.getPrinterAttributes,
    requestId: requestId,
    printerUri: printerUri,
    requestingUserName: requestingUserName,
  );
}

/// Builds a Check-For-New-Printer-Firmware request (§5.1.1).
IppMessage buildCheckForNewPrinterFirmwareRequest({
  required String printerUri,
  required int requestId,
  String requestingUserName = '',
}) {
  return IppMessage.request(
    operationId: IppOperationId.checkForNewPrinterFirmware,
    requestId: requestId,
    printerUri: printerUri,
    requestingUserName: requestingUserName,
  );
}

/// Builds an Update-Printer-Firmware request (§5.2.1). At most one of
/// [delayUpdateUntil] (a [DelayUpdateUntil] keyword) or
/// [delayUpdateUntilDateTime] may be supplied.
IppMessage buildUpdatePrinterFirmwareRequest({
  required String printerUri,
  required int requestId,
  String requestingUserName = '',
  String? delayUpdateUntil,
  DateTime? delayUpdateUntilDateTime,
}) {
  if (delayUpdateUntil != null && delayUpdateUntilDateTime != null) {
    throw ConflictingDelayAttributesError();
  }
  return IppMessage.request(
    operationId: IppOperationId.updatePrinterFirmware,
    requestId: requestId,
    printerUri: printerUri,
    requestingUserName: requestingUserName,
    operationAttributes: [
      if (delayUpdateUntil != null)
        IppAttribute.single(FwOperationAttr.delayUpdateUntil, IppKeyword(delayUpdateUntil)),
      if (delayUpdateUntilDateTime != null)
        IppAttribute.single(
          FwOperationAttr.delayUpdateUntilDateTime,
          IppDateTime.fromDateTimeUtc(delayUpdateUntilDateTime),
        ),
    ],
  );
}
