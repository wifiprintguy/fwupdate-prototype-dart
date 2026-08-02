import 'dart:convert';
import 'dart:typed_data';

import 'ipp_constants.dart';

/// A single tagged IPP attribute value (RFC 8010 §3.5).
///
/// Covers both "in-band" values (integer, keyword, uri, ...) and
/// "out-of-band" values (`no-value`, `unknown`, `unsupported`) — the spec
/// leans heavily on the out-of-band values to distinguish "never checked"
/// from "checked but repository unreachable" (see FWUPDATE §6.3), so both
/// cases have to be first-class here rather than bolted on.
sealed class IppValue {
  const IppValue();

  int get tag;

  Uint8List get _bytes;

  /// Decodes a single value from its wire tag + raw value bytes.
  factory IppValue.decode(int tag, Uint8List bytes) {
    return switch (tag) {
      IppOutOfBandTag.unsupported => const IppUnsupported(),
      IppOutOfBandTag.unknown => const IppUnknown(),
      IppOutOfBandTag.noValue => const IppNoValue(),
      IppValueTag.integer => IppInteger(_decodeInt32(bytes)),
      IppValueTag.boolean => IppBoolean(bytes.isNotEmpty && bytes[0] != 0x00),
      IppValueTag.enumValue => IppEnum(_decodeInt32(bytes)),
      IppValueTag.octetString => IppOctetString(bytes),
      IppValueTag.dateTime => IppDateTime.decode(bytes),
      IppValueTag.textWithoutLanguage => IppText(utf8.decode(bytes)),
      IppValueTag.nameWithoutLanguage => IppName(utf8.decode(bytes)),
      IppValueTag.keyword => IppKeyword(utf8.decode(bytes)),
      IppValueTag.uri => IppUri(utf8.decode(bytes)),
      IppValueTag.charset => IppCharset(utf8.decode(bytes)),
      IppValueTag.naturalLanguage => IppNaturalLanguage(utf8.decode(bytes)),
      _ => throw FormatException(
        'Unsupported IPP value tag 0x${tag.toRadixString(16)}',
      ),
    };
  }

  static int _decodeInt32(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return data.getInt32(0, Endian.big);
  }
}

/// The `unsupported` out-of-band value: this attribute name/value was
/// rejected by the receiver (returned in a Group 3 "Unsupported Attributes").
final class IppUnsupported extends IppValue {
  const IppUnsupported();
  @override
  int get tag => IppOutOfBandTag.unsupported;
  @override
  Uint8List get _bytes => Uint8List(0);
  @override
  String toString() => 'unsupported';
}

/// The `unknown` out-of-band value (FWUPDATE §6.3: "the Printer was unable
/// to contact the configured Firmware Repository or unable to get
/// actionable information from it").
final class IppUnknown extends IppValue {
  const IppUnknown();
  @override
  int get tag => IppOutOfBandTag.unknown;
  @override
  Uint8List get _bytes => Uint8List(0);
  @override
  String toString() => 'unknown';
}

/// The `no-value` out-of-band value (FWUPDATE §6.3: "the Printer has never
/// checked for new Firmware").
final class IppNoValue extends IppValue {
  const IppNoValue();
  @override
  int get tag => IppOutOfBandTag.noValue;
  @override
  Uint8List get _bytes => Uint8List(0);
  @override
  String toString() => 'no-value';
}

final class IppInteger extends IppValue {
  const IppInteger(this.value);
  final int value;
  @override
  int get tag => IppValueTag.integer;
  @override
  Uint8List get _bytes =>
      (ByteData(4)..setInt32(0, value, Endian.big)).buffer.asUint8List();
  @override
  String toString() => '$value';
}

final class IppBoolean extends IppValue {
  const IppBoolean(this.value);
  final bool value;
  @override
  int get tag => IppValueTag.boolean;
  @override
  Uint8List get _bytes => Uint8List.fromList([value ? 0x01 : 0x00]);
  @override
  String toString() => '$value';
}

final class IppEnum extends IppValue {
  const IppEnum(this.value);
  final int value;
  @override
  int get tag => IppValueTag.enumValue;
  @override
  Uint8List get _bytes =>
      (ByteData(4)..setInt32(0, value, Endian.big)).buffer.asUint8List();
  @override
  String toString() => '0x${value.toRadixString(16).padLeft(4, '0')}';
}

final class IppOctetString extends IppValue {
  const IppOctetString(this.value);
  final Uint8List value;
  @override
  int get tag => IppValueTag.octetString;
  @override
  Uint8List get _bytes => value;
  @override
  String toString() => value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// RFC 2579 `DateAndTime`, the 11-octet structure IPP uses for `dateTime`
/// values (RFC 8010 §3.9). Kept independent of [DateTime]'s timezone
/// handling so a message can carry an explicit UTC offset.
final class IppDateTime extends IppValue {
  const IppDateTime({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    this.deciSecond = 0,
    this.utcDirection = '+',
    this.utcHours = 0,
    this.utcMinutes = 0,
  });

  factory IppDateTime.fromDateTimeUtc(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return IppDateTime(
      year: utc.year,
      month: utc.month,
      day: utc.day,
      hour: utc.hour,
      minute: utc.minute,
      second: utc.second,
      deciSecond: utc.millisecond ~/ 100,
    );
  }

  factory IppDateTime.decode(Uint8List bytes) {
    if (bytes.length < 11) {
      throw FormatException('IPP dateTime value must be 11 octets');
    }
    final data = ByteData.sublistView(bytes);
    return IppDateTime(
      year: data.getUint16(0, Endian.big),
      month: bytes[2],
      day: bytes[3],
      hour: bytes[4],
      minute: bytes[5],
      second: bytes[6],
      deciSecond: bytes[7],
      utcDirection: String.fromCharCode(bytes[8]),
      utcHours: bytes[9],
      utcMinutes: bytes[10],
    );
  }

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final int deciSecond;
  final String utcDirection; // '+' or '-'
  final int utcHours;
  final int utcMinutes;

  DateTime toDateTimeUtc() {
    final sign = utcDirection == '-' ? -1 : 1;
    final localAsUtc = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      deciSecond * 100,
    );
    return localAsUtc.subtract(
      Duration(hours: sign * utcHours, minutes: sign * utcMinutes),
    );
  }

  @override
  int get tag => IppValueTag.dateTime;

  @override
  Uint8List get _bytes {
    final bytes = Uint8List(11);
    final data = ByteData.sublistView(bytes);
    data.setUint16(0, year, Endian.big);
    bytes[2] = month;
    bytes[3] = day;
    bytes[4] = hour;
    bytes[5] = minute;
    bytes[6] = second;
    bytes[7] = deciSecond;
    bytes[8] = utcDirection.codeUnitAt(0);
    bytes[9] = utcHours;
    bytes[10] = utcMinutes;
    return bytes;
  }

  @override
  String toString() => toDateTimeUtc().toIso8601String();
}

sealed class _IppStringValue extends IppValue {
  const _IppStringValue(this.value);
  final String value;
  @override
  Uint8List get _bytes => Uint8List.fromList(utf8.encode(value));
  @override
  String toString() => value;
}

final class IppText extends _IppStringValue {
  const IppText(super.value);
  @override
  int get tag => IppValueTag.textWithoutLanguage;
}

final class IppName extends _IppStringValue {
  const IppName(super.value);
  @override
  int get tag => IppValueTag.nameWithoutLanguage;
}

final class IppKeyword extends _IppStringValue {
  const IppKeyword(super.value);
  @override
  int get tag => IppValueTag.keyword;
}

final class IppUri extends _IppStringValue {
  const IppUri(super.value);
  @override
  int get tag => IppValueTag.uri;
}

final class IppCharset extends _IppStringValue {
  const IppCharset(super.value);
  @override
  int get tag => IppValueTag.charset;
}

final class IppNaturalLanguage extends _IppStringValue {
  const IppNaturalLanguage(super.value);
  @override
  int get tag => IppValueTag.naturalLanguage;
}

/// Package-private accessor so [IppAttribute]/message encoding can reach
/// the raw value bytes without exposing a public mutable API.
extension IppValueBytes on IppValue {
  Uint8List get wireBytes => _bytes;
}
