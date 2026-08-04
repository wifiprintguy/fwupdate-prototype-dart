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

/// FWUPDATE itself never mentions the IPP `version-number` field — it only
/// borrows baseline attribute/operation semantics from [STD92] (RFC
/// 8010/8011, IPP/1.1), independent of whatever version-number a given
/// packet declares. [STD92] isn't a stand-in for "IPP/1.1 only": real
/// IPP/2.0 printers still implement exactly those STD92-inherited
/// behaviors, just under a newer version header.
///
/// This isn't purely theoretical: a libcups-based prototype of FWUPDATE
/// failed its own `.test` file when a Printer responded with 1.1 instead
/// of 2.0, even though nothing in the FWUPDATE draft itself says 2.0 is
/// required. That's corroborating real-world evidence that PWG's own
/// conformance tooling for this extension assumes an IPP/2.0 baseline —
/// hence defaulting to 2.0 here rather than 1.1, while still negotiating
/// down for a request that genuinely declares an older version.
abstract final class IppVersion {
  /// The version this project's own Client-side request builders declare
  /// by default. IPP/2.0 is what modern Clients/Printers actually speak on
  /// the wire today, so that's the more representative default for a test
  /// harness — a request explicitly built with an older version (e.g. to
  /// test negotiation itself) still works via [IppMessage]'s constructor
  /// parameters.
  static const int major = 2;
  static const int minor = 0;

  /// The version a Printer should declare in its response, per standard
  /// IPP version-negotiation practice: echo the request's version if it's
  /// at or below what this project supports, otherwise cap at the highest
  /// version supported ([major].[minor]).
  static (int major, int minor) negotiateResponseVersion(
    int requestMajor,
    int requestMinor,
  ) {
    final requestIsSupported =
        requestMajor < major || (requestMajor == major && requestMinor <= minor);
    return requestIsSupported ? (requestMajor, requestMinor) : (major, minor);
  }
}

/// The HTTP content-type used to carry IPP messages.
const String ippContentType = 'application/ipp';
