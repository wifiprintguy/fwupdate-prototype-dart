import 'dart:convert';
import 'dart:typed_data';

import 'ipp_constants.dart';
import 'ipp_value.dart';

/// A named, possibly multi-valued attribute (RFC 8010 §3.5.1, `1setOf`).
final class IppAttribute {
  IppAttribute(this.name, List<IppValue> values)
    : values = List.unmodifiable(values);

  factory IppAttribute.single(String name, IppValue value) =>
      IppAttribute(name, [value]);

  final String name;
  final List<IppValue> values;

  IppValue get value => values.first;

  /// True for the out-of-band values FWUPDATE relies on throughout §6.3 to
  /// distinguish "never checked" ([IppNoValue]) from "checked but the
  /// repository could not be reached" ([IppUnknown]).
  bool get isOutOfBand =>
      values.length == 1 &&
      (value is IppNoValue || value is IppUnknown || value is IppUnsupported);

  @override
  String toString() => '$name = ${values.join(', ')}';
}

/// One delimited group of attributes, e.g. "Operation Attributes" or
/// "Printer Attributes" (RFC 8010 §3.5.1).
final class IppAttributeGroup {
  IppAttributeGroup(this.tag, List<IppAttribute> attributes)
    : attributes = List.unmodifiable(attributes);

  final int tag;
  final List<IppAttribute> attributes;

  IppAttribute? operator [](String name) =>
      attributes.where((a) => a.name == name).firstOrNull;

  String get tagName => switch (tag) {
    IppDelimiterTag.operationAttributes => 'operation-attributes',
    IppDelimiterTag.jobAttributes => 'job-attributes',
    IppDelimiterTag.printerAttributes => 'printer-attributes',
    IppDelimiterTag.unsupportedAttributes => 'unsupported-attributes',
    _ => '0x${tag.toRadixString(16)}',
  };
}

/// An IPP request or response (RFC 8010 §3.1). The same class models both
/// directions: [operationIdOrStatusCode] is the operation id on a request
/// and the status code on a response.
final class IppMessage {
  IppMessage({
    required this.operationIdOrStatusCode,
    required this.requestId,
    required List<IppAttributeGroup> groups,
    this.versionMajor = IppVersion.major,
    this.versionMinor = IppVersion.minor,
  }) : groups = List.unmodifiable(groups);

  final int versionMajor;
  final int versionMinor;

  /// Returns a copy declaring a different version — for a Printer to apply
  /// [IppVersion.negotiateResponseVersion] to an otherwise-finished
  /// response without every response-building call site needing to know
  /// about negotiation.
  IppMessage copyWithVersion(int versionMajor, int versionMinor) => IppMessage(
    versionMajor: versionMajor,
    versionMinor: versionMinor,
    operationIdOrStatusCode: operationIdOrStatusCode,
    requestId: requestId,
    groups: groups,
  );
  final int operationIdOrStatusCode;
  final int requestId;
  final List<IppAttributeGroup> groups;

  int get statusCode => operationIdOrStatusCode;
  int get operationId => operationIdOrStatusCode;
  bool get isSuccessful => IppStatusCode.isSuccessful(statusCode);

  IppAttributeGroup? group(int tag) =>
      groups.where((g) => g.tag == tag).firstOrNull;

  IppAttributeGroup get operationAttributes =>
      group(IppDelimiterTag.operationAttributes) ??
      IppAttributeGroup(IppDelimiterTag.operationAttributes, const []);

  IppAttributeGroup get printerAttributes =>
      group(IppDelimiterTag.printerAttributes) ??
      IppAttributeGroup(IppDelimiterTag.printerAttributes, const []);

  /// Convenience builder for a well-formed request: automatically supplies
  /// `attributes-charset`/`attributes-natural-language` as the first two
  /// operation attributes, which every operation in this project's scope
  /// requires (e.g. FWUPDATE §5.1.1, §5.2.1).
  factory IppMessage.request({
    required int operationId,
    required int requestId,
    required String printerUri,
    List<IppAttribute> operationAttributes = const [],
    String requestingUserName = 'test-user',
  }) {
    return IppMessage(
      operationIdOrStatusCode: operationId,
      requestId: requestId,
      groups: [
        IppAttributeGroup(IppDelimiterTag.operationAttributes, [
          IppAttribute.single('attributes-charset', const IppCharset('utf-8')),
          IppAttribute.single(
            'attributes-natural-language',
            const IppNaturalLanguage('en'),
          ),
          IppAttribute.single('printer-uri', IppUri(printerUri)),
          if (requestingUserName.isNotEmpty)
            IppAttribute.single(
              'requesting-user-name',
              IppName(requestingUserName),
            ),
          ...operationAttributes,
        ]),
      ],
    );
  }

  /// Convenience builder for a response carrying only a status code and
  /// optional status message (no printer attributes).
  factory IppMessage.statusResponse({
    required int statusCode,
    required int requestId,
    String? statusMessage,
    List<IppAttribute> printerAttributes = const [],
    List<IppAttribute> unsupportedAttributes = const [],
  }) {
    return IppMessage(
      operationIdOrStatusCode: statusCode,
      requestId: requestId,
      groups: [
        IppAttributeGroup(IppDelimiterTag.operationAttributes, [
          IppAttribute.single('attributes-charset', const IppCharset('utf-8')),
          IppAttribute.single(
            'attributes-natural-language',
            const IppNaturalLanguage('en'),
          ),
          if (statusMessage != null)
            IppAttribute.single('status-message', IppText(statusMessage)),
        ]),
        if (printerAttributes.isNotEmpty)
          IppAttributeGroup(IppDelimiterTag.printerAttributes, printerAttributes),
        if (unsupportedAttributes.isNotEmpty)
          IppAttributeGroup(
            IppDelimiterTag.unsupportedAttributes,
            unsupportedAttributes,
          ),
      ],
    );
  }

  Uint8List encode() {
    final out = BytesBuilder();
    out.addByte(versionMajor);
    out.addByte(versionMinor);
    _writeUint16(out, operationIdOrStatusCode);
    _writeUint32(out, requestId);

    for (final group in groups) {
      out.addByte(group.tag);
      for (final attribute in group.attributes) {
        for (var i = 0; i < attribute.values.length; i++) {
          final value = attribute.values[i];
          out.addByte(value.tag);
          final isAdditionalValue = i > 0;
          final nameBytes = isAdditionalValue
              ? const <int>[]
              : utf8.encode(attribute.name);
          _writeUint16(out, nameBytes.length);
          out.add(nameBytes);
          final valueBytes = value.wireBytes;
          _writeUint16(out, valueBytes.length);
          out.add(valueBytes);
        }
      }
    }
    out.addByte(IppDelimiterTag.endOfAttributes);
    return out.toBytes();
  }

  static IppMessage decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 0;

    final versionMajor = bytes[offset++];
    final versionMinor = bytes[offset++];
    final operationIdOrStatusCode = data.getUint16(offset, Endian.big);
    offset += 2;
    final requestId = data.getUint32(offset, Endian.big);
    offset += 4;

    final groups = <IppAttributeGroup>[];
    List<IppAttribute>? currentGroupAttributes;
    int? currentGroupTag;
    IppAttribute? currentAttribute;

    void flushGroup() {
      if (currentGroupTag != null && currentGroupAttributes != null) {
        groups.add(IppAttributeGroup(currentGroupTag!, currentGroupAttributes!));
      }
      currentGroupAttributes = null;
      currentGroupTag = null;
      currentAttribute = null;
    }

    while (offset < bytes.length) {
      final tag = bytes[offset++];
      if (tag == IppDelimiterTag.endOfAttributes) {
        flushGroup();
        break;
      }
      if (tag <= 0x0F) {
        // Begin a new attribute-group.
        flushGroup();
        currentGroupTag = tag;
        currentGroupAttributes = <IppAttribute>[];
        currentAttribute = null;
        continue;
      }

      final nameLength = data.getUint16(offset, Endian.big);
      offset += 2;
      final name = utf8.decode(bytes.sublist(offset, offset + nameLength));
      offset += nameLength;
      final valueLength = data.getUint16(offset, Endian.big);
      offset += 2;
      final valueBytes = bytes.sublist(offset, offset + valueLength);
      offset += valueLength;

      final value = IppValue.decode(tag, valueBytes);

      if (name.isEmpty && currentAttribute != null) {
        // Additional value of the previous (possibly multi-valued)
        // attribute.
        currentAttribute = IppAttribute(currentAttribute!.name, [
          ...currentAttribute!.values,
          value,
        ]);
        currentGroupAttributes!
          ..removeLast()
          ..add(currentAttribute!);
      } else {
        currentAttribute = IppAttribute.single(name, value);
        currentGroupAttributes ??= <IppAttribute>[];
        currentGroupAttributes!.add(currentAttribute!);
      }
    }

    return IppMessage(
      versionMajor: versionMajor,
      versionMinor: versionMinor,
      operationIdOrStatusCode: operationIdOrStatusCode,
      requestId: requestId,
      groups: groups,
    );
  }

  static void _writeUint16(BytesBuilder out, int value) {
    out.addByte((value >> 8) & 0xFF);
    out.addByte(value & 0xFF);
  }

  static void _writeUint32(BytesBuilder out, int value) {
    out.addByte((value >> 24) & 0xFF);
    out.addByte((value >> 16) & 0xFF);
    out.addByte((value >> 8) & 0xFF);
    out.addByte(value & 0xFF);
  }

  @override
  String toString() {
    final buffer = StringBuffer(
      'IppMessage(op/status=0x${operationIdOrStatusCode.toRadixString(16)}, '
      'requestId=$requestId)',
    );
    for (final group in groups) {
      buffer.writeln();
      buffer.writeln('  [${group.tagName}]');
      for (final attribute in group.attributes) {
        buffer.writeln('    $attribute');
      }
    }
    return buffer.toString();
  }
}
