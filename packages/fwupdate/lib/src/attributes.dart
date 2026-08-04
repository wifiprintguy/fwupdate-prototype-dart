/// Attribute names and keyword vocabularies defined by IPP Firmware Update
/// Extensions v1.0 (FWUPDATE) §6.
///
/// Note on naming drift in the draft: the working draft (Status: Prototype,
/// 2026-07-29) is not internally consistent — Table 1 (§4.2) and the
/// Check-For-New-Printer-Firmware response text (§5.1.2) refer to
/// `printer-new-firmware-support-uri` / `printer-new-firmware-last-checked`,
/// while the normative per-attribute subsections (§6.3.5, §6.3.2) define
/// `printer-new-firmware-info-uri` and `printer-new-firmware-check-date-time`
/// respectively, and Table 1's "Section" column is off by one throughout.
/// This implementation treats the numbered §6.3.x subsections as
/// authoritative and uses their names consistently everywhere.
library;

/// Operation attributes (§6.1).
abstract final class FwOperationAttr {
  static const delayUpdateUntil = 'delay-update-until'; // §6.1.1
  static const delayUpdateUntilDateTime = 'delay-update-until-date-time'; // §6.1.2
}

/// Printer description attributes (§6.2).
abstract final class FwDescriptionAttr {
  static const delayUpdateUntilSupported = 'delay-update-until-supported'; // §6.2.1
  static const newFirmwarePolicyConfigured =
      'printer-new-firmware-policy-configured'; // §6.2.2
  static const newFirmwarePolicySupported =
      'printer-new-firmware-policy-supported'; // §6.2.3
  static const firmwareRepositoryUriConfigured =
      'printer-firmware-repository-uri-configured'; // §6.2.4
  static const firmwareRepositoryUriSupported =
      'printer-firmware-repository-uri-supported'; // §6.2.5
}

/// Printer status attributes (§6.3).
abstract final class FwStatusAttr {
  static const firmwareInfoUri = 'printer-firmware-info-uri'; // §6.3.1 (current firmware)
  static const newFirmwareCheckDateTime =
      'printer-new-firmware-check-date-time'; // §6.3.2
  static const newFirmwareDelayedUntil =
      'printer-new-firmware-delayed-until'; // §6.3.3
  static const newFirmwareDelayedUntilDateTime =
      'printer-new-firmware-delayed-until-date-time'; // §6.3.4
  static const newFirmwareInfoUri = 'printer-new-firmware-info-uri'; // §6.3.5
  static const newFirmwareKOctets = 'printer-new-firmware-k-octets'; // §6.3.6
  static const newFirmwareName = 'printer-new-firmware-name'; // §6.3.7
  static const newFirmwarePatches = 'printer-new-firmware-patches'; // §6.3.8
  static const newFirmwareStringVersion =
      'printer-new-firmware-string-version'; // §6.3.9
  static const newFirmwareUrgency = 'printer-new-firmware-urgency'; // §6.3.10
  static const newFirmwareVersion = 'printer-new-firmware-version'; // §6.3.11

  /// The attributes that describe the discovered Firmware itself (as
  /// opposed to [newFirmwareCheckDateTime], which the Printer keeps
  /// up-to-date even when the repository can't be reached, per §6.3.2's
  /// explicit note). These seven go out-of-band together: `no-value` if
  /// the Printer has never checked, `unknown` if the last check failed to
  /// reach/read the repository.
  static const newFirmwareDataGroup = [
    newFirmwareInfoUri,
    newFirmwareKOctets,
    newFirmwareName,
    newFirmwarePatches,
    newFirmwareStringVersion,
    newFirmwareUrgency,
    newFirmwareVersion,
  ];

  /// The full set of attributes §5.2's body text says the Printer clears
  /// back to `no-value` once an Update-Printer-Firmware completes
  /// successfully — [newFirmwareDataGroup] plus [newFirmwareCheckDateTime]
  /// itself, since a fresh check hasn't happened since installing.
  static const newFirmwareStatusGroup = [
    newFirmwareCheckDateTime,
    ...newFirmwareDataGroup,
  ];
}

/// Attributes describing the Printer's *currently installed* Firmware.
/// FWUPDATE doesn't define these itself — they're from [PWG 5100.13] "IPP
/// Driver Replacement Extensions v2.0" — but Table 1 (§4.2) explicitly
/// cross-references them as the "Current Firmware Status Attribute"
/// counterpart to several `printer-new-firmware-*` attributes, so a
/// Printer implementing FWUPDATE needs them to make that before/after
/// comparison meaningful. `printer-firmware-info-uri` is the one exception
/// that lives in [FwStatusAttr] instead, since FWUPDATE §6.3.1 defines it
/// directly (REQUIRED) rather than merely referencing PWG 5100.13.
abstract final class CurrentFirmwareAttr {
  static const name = 'printer-firmware-name';
  static const patches = 'printer-firmware-patches';
  static const stringVersion = 'printer-firmware-string-version';
  static const version = 'printer-firmware-version';
}

/// Table 2 — keywords for the `delay-update-until` attribute (§6.1.1).
abstract final class DelayUpdateUntil {
  static const noDelay = 'no-delay';
  static const indefinite = 'indefinite';
  static const dayTime = 'day-time';
  static const evening = 'evening';
  static const night = 'night';
  static const secondShift = 'second-shift';
  static const thirdShift = 'third-shift';
  static const weekend = 'weekend';

  static const all = [
    noDelay,
    indefinite,
    dayTime,
    evening,
    night,
    secondShift,
    thirdShift,
    weekend,
  ];
}

/// Table 3 — keywords for `printer-new-firmware-policy-supported` (§6.2.3).
abstract final class NewFirmwarePolicy {
  /// Printer automatically discovers, downloads, validates, installs and
  /// activates new Firmware.
  static const auto = 'auto';

  /// Printer discovers new Firmware but does not download/validate/
  /// install/activate it.
  static const check = 'check';

  /// Printer discovers and validates/installs/activates new Firmware only
  /// using the operations defined in FWUPDATE §5 (i.e. only when a Client
  /// asks).
  static const directed = 'directed';

  /// Printer automatically discovers, downloads and validates new Firmware
  /// but refrains from installing it.
  static const download = 'download';

  static const all = [auto, check, directed, download];
}

/// Table 4 — keywords for `printer-new-firmware-urgency` (§6.3.10).
abstract final class NewFirmwareUrgency {
  static const bugfix = 'bugfix';
  static const feature = 'feature';
  static const security = 'security';

  static const all = [bugfix, feature, security];
}

/// The `fwupdate` keyword this specification adds to `ipp-features-supported`
/// (§7.1).
const String ippFeatureFwupdate = 'fwupdate';
