/// Wire-format constants from RFC 8010 (encoding) and RFC 8011 (model),
/// limited to the subset this project needs.
library;

/// Delimiter tags. These begin an attribute group, or end the attribute
/// list entirely. They occupy the same one-byte tag space as value tags,
/// but are always < 0x10.
abstract final class IppDelimiterTag {
  static const int operationAttributes = 0x01;
  static const int jobAttributes = 0x02;
  static const int endOfAttributes = 0x03;
  static const int printerAttributes = 0x04;
  static const int unsupportedAttributes = 0x05;
}

/// Out-of-band value tags (RFC 8010 §3.5.2). These attributes carry no
/// value bytes; the tag alone communicates the meaning.
abstract final class IppOutOfBandTag {
  static const int unsupported = 0x10;
  static const int unknown = 0x12;
  static const int noValue = 0x13;
}

/// "in-band" value tags for the value syntaxes this project needs.
abstract final class IppValueTag {
  static const int integer = 0x21;
  static const int boolean = 0x22;
  static const int enumValue = 0x23;
  static const int octetString = 0x30;
  static const int dateTime = 0x31;
  static const int textWithoutLanguage = 0x41;
  static const int nameWithoutLanguage = 0x42;
  static const int keyword = 0x44;
  static const int uri = 0x45;
  static const int charset = 0x47;
  static const int naturalLanguage = 0x48;
}

/// Operation ids. Values below 0x0070 are from RFC 8011 (a small subset used
/// by this prototype) plus the two operations defined by FWUPDATE (§7.2 /
/// §12.4 of the FWUPDATE spec).
abstract final class IppOperationId {
  static const int getPrinterAttributes = 0x000B;
  static const int checkForNewPrinterFirmware = 0x006B;
  static const int updatePrinterFirmware = 0x006C;
}

/// Status codes from RFC 8011 §4.1.2, limited to the ones this project uses.
abstract final class IppStatusCode {
  static const int successfulOk = 0x0000;
  static const int successfulOkIgnoredOrSubstitutedAttributes = 0x0001;

  static const int clientErrorBadRequest = 0x0400;
  static const int clientErrorForbidden = 0x0401;
  static const int clientErrorNotAuthenticated = 0x0402;
  static const int clientErrorNotAuthorized = 0x0403;
  static const int clientErrorNotFound = 0x0406;
  static const int clientErrorAttributesOrValuesNotSupported = 0x040B;
  static const int clientErrorConflictingAttributes = 0x040E;

  static const int serverErrorInternalError = 0x0500;
  static const int serverErrorOperationNotSupported = 0x0501;
  static const int serverErrorTemporaryError = 0x0505;

  static bool isSuccessful(int statusCode) => statusCode < 0x0100;

  static String name(int statusCode) => switch (statusCode) {
    successfulOk => 'successful-ok',
    successfulOkIgnoredOrSubstitutedAttributes =>
      'successful-ok-ignored-or-substituted-attributes',
    clientErrorBadRequest => 'client-error-bad-request',
    clientErrorForbidden => 'client-error-forbidden',
    clientErrorNotAuthenticated => 'client-error-not-authenticated',
    clientErrorNotAuthorized => 'client-error-not-authorized',
    clientErrorNotFound => 'client-error-not-found',
    clientErrorAttributesOrValuesNotSupported =>
      'client-error-attributes-or-values-not-supported',
    clientErrorConflictingAttributes => 'client-error-conflicting-attributes',
    serverErrorInternalError => 'server-error-internal-error',
    serverErrorOperationNotSupported => 'server-error-operation-not-supported',
    serverErrorTemporaryError => 'server-error-temporary-error',
    _ => '0x${statusCode.toRadixString(16).padLeft(4, '0')}',
  };
}

/// The IPP version this project's messages declare (IPP/1.1, per [STD92]
/// a.k.a. RFC 8011, which the FWUPDATE spec builds on).
abstract final class IppVersion {
  static const int major = 1;
  static const int minor = 1;
}

/// The HTTP content-type used to carry IPP messages.
const String ippContentType = 'application/ipp';
