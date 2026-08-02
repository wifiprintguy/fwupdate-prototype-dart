import 'dart:convert';
import 'dart:typed_data';

import 'package:ipp/ipp.dart';

import 'attributes.dart';

/// A snapshot of the "new Firmware is available" attribute bundle
/// (§6.3.5-§6.3.11, minus `printer-new-firmware-check-date-time` which the
/// Printer tracks separately — see [FwStatusAttr.newFirmwareDataGroup]).
///
/// This is the Printer app's in-memory model of "what the simulated
/// repository currently offers", and the Client app's parsed view of the
/// same thing after a Get-Printer-Attributes response.
final class FirmwareInfo {
  const FirmwareInfo({
    required this.names,
    required this.patches,
    required this.kOctets,
    required this.stringVersions,
    required this.urgency,
    required this.versions,
    this.infoUri,
  });

  final List<String> names;
  final List<String> patches;
  final int kOctets;
  final List<String> stringVersions;

  /// One of [NewFirmwareUrgency]'s keywords.
  final String urgency;

  /// `octetString(MAX)` values (§6.3.11) — modeled as raw bytes since the
  /// spec leaves the version encoding to the manufacturer.
  final List<Uint8List> versions;

  final Uri? infoUri;

  /// A reasonable default used by scenario presets: a single-component
  /// firmware update.
  factory FirmwareInfo.simple({
    required String name,
    required String stringVersion,
    required String urgency,
    int kOctets = 45000,
    String? patch,
    Uri? infoUri,
  }) {
    return FirmwareInfo(
      names: [name],
      patches: [patch ?? 'none'],
      kOctets: kOctets,
      stringVersions: [stringVersion],
      urgency: urgency,
      versions: [Uint8List.fromList(utf8.encode(stringVersion))],
      infoUri: infoUri,
    );
  }

  List<IppAttribute> toAttributes() => [
    IppAttribute(FwStatusAttr.newFirmwareName, names.map(IppName.new).toList()),
    IppAttribute(FwStatusAttr.newFirmwarePatches, patches.map(IppText.new).toList()),
    IppAttribute.single(FwStatusAttr.newFirmwareKOctets, IppInteger(kOctets)),
    IppAttribute(
      FwStatusAttr.newFirmwareStringVersion,
      stringVersions.map(IppText.new).toList(),
    ),
    IppAttribute.single(FwStatusAttr.newFirmwareUrgency, IppKeyword(urgency)),
    IppAttribute(
      FwStatusAttr.newFirmwareVersion,
      versions.map(IppOctetString.new).toList(),
    ),
    if (infoUri != null)
      IppAttribute.single(FwStatusAttr.newFirmwareInfoUri, IppUri(infoUri.toString())),
  ];

  /// Parses the bundle back out of a Printer/Get-Printer-Attributes
  /// response's attribute group. Returns `null` if any of the out-of-band
  /// states (`no-value`/`unknown`) is present instead of a real value —
  /// callers should check [FwOutOfBandState.of] first to distinguish "no
  /// update available" from "couldn't tell".
  static FirmwareInfo? tryParse(IppAttributeGroup printerAttributes) {
    final nameAttr = printerAttributes[FwStatusAttr.newFirmwareName];
    if (nameAttr == null || nameAttr.isOutOfBand) return null;

    IppAttribute? attr(String name) => printerAttributes[name];
    List<String> strings(String name) =>
        attr(name)?.values.map((v) => v.toString()).toList() ?? const [];

    final kOctetsAttr = attr(FwStatusAttr.newFirmwareKOctets);
    final kOctets = kOctetsAttr != null && kOctetsAttr.value is IppInteger
        ? (kOctetsAttr.value as IppInteger).value
        : 0;

    final urgencyAttr = attr(FwStatusAttr.newFirmwareUrgency);
    final urgency = urgencyAttr != null && !urgencyAttr.isOutOfBand
        ? urgencyAttr.value.toString()
        : '';

    final versionAttr = attr(FwStatusAttr.newFirmwareVersion);
    final versions = versionAttr != null && !versionAttr.isOutOfBand
        ? versionAttr.values
              .whereType<IppOctetString>()
              .map((v) => v.value)
              .toList()
        : const <Uint8List>[];

    final infoUriAttr = attr(FwStatusAttr.newFirmwareInfoUri);
    final infoUri = infoUriAttr != null && !infoUriAttr.isOutOfBand
        ? Uri.tryParse(infoUriAttr.value.toString())
        : null;

    return FirmwareInfo(
      names: strings(FwStatusAttr.newFirmwareName),
      patches: strings(FwStatusAttr.newFirmwarePatches),
      kOctets: kOctets,
      stringVersions: strings(FwStatusAttr.newFirmwareStringVersion),
      urgency: urgency,
      versions: versions,
      infoUri: infoUri,
    );
  }
}

/// Which out-of-band state (if any) the `printer-new-firmware-*` data
/// attributes (§6.3.5-6.3.11) are currently reporting.
enum FwOutOfBandState {
  /// A real value is present — new Firmware is available.
  none,

  /// `no-value`: the Printer has never checked for new Firmware.
  neverChecked,

  /// `unknown`: the Printer checked but couldn't reach the repository or
  /// get actionable information from it.
  unknown;

  static FwOutOfBandState of(IppAttributeGroup printerAttributes) {
    final nameAttr = printerAttributes[FwStatusAttr.newFirmwareName];
    if (nameAttr == null) return FwOutOfBandState.neverChecked;
    return switch (nameAttr.value) {
      IppNoValue() => FwOutOfBandState.neverChecked,
      IppUnknown() => FwOutOfBandState.unknown,
      _ => FwOutOfBandState.none,
    };
  }
}

/// Builds the seven [FwStatusAttr.newFirmwareDataGroup] attributes as a
/// single out-of-band value (`no-value` or `unknown`), per §6.3.5-6.3.11's
/// identical out-of-band wording.
List<IppAttribute> buildOutOfBandFirmwareDataAttributes(IppValue outOfBandValue) {
  assert(
    outOfBandValue is IppNoValue || outOfBandValue is IppUnknown,
    'Expected an out-of-band value (no-value or unknown)',
  );
  return FwStatusAttr.newFirmwareDataGroup
      .map((name) => IppAttribute.single(name, outOfBandValue))
      .toList();
}
