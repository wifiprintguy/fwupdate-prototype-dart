/// Attribute names and keyword vocabularies defined by IPP Firmware Update
/// Extensions v1.0 (FWUPDATE) §6, as of the 2026-10-31 working draft.
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
  static const firmwareUpdateDateTime =
      'printer-firmware-update-date-time'; // §6.3.2 (current firmware)
  static const newFirmwareCheckDateTime =
      'printer-new-firmware-check-date-time'; // §6.3.3
  static const newFirmwareDelayedUntil =
      'printer-new-firmware-delayed-until'; // §6.3.4
  static const newFirmwareDelayedUntilDateTime =
      'printer-new-firmware-delayed-until-date-time'; // §6.3.5
  static const newFirmwareInfoUri = 'printer-new-firmware-info-uri'; // §6.3.6
  static const newFirmwareKOctets = 'printer-new-firmware-k-octets'; // §6.3.7
  static const newFirmwareName = 'printer-new-firmware-name'; // §6.3.8
  static const newFirmwareOfflineTime =
      'printer-new-firmware-offline-time'; // §6.3.9
  static const newFirmwarePatches = 'printer-new-firmware-patches'; // §6.3.10
  static const newFirmwareStringVersion =
      'printer-new-firmware-string-version'; // §6.3.11
  static const newFirmwareUrgency = 'printer-new-firmware-urgency'; // §6.3.12
  static const newFirmwareVersion = 'printer-new-firmware-version'; // §6.3.13

  /// The Table 1 attributes that describe the discovered Firmware itself
  /// and share the same out-of-band rules: `no-value` if the Printer has
  /// never checked (or found nothing), `unknown` if the last check failed
  /// to reach or read the repository. `firmware-update-available` is listed
  /// if and only if these report real values (§7.3.9).
  static const newFirmwareDataGroup = [
    newFirmwareInfoUri,
    newFirmwareKOctets,
    newFirmwareName,
    newFirmwareOfflineTime,
    newFirmwarePatches,
    newFirmwareStringVersion,
    newFirmwareUrgency,
    newFirmwareVersion,
  ];

  /// The attributes this Printer resets to `no-value` once a Firmware
  /// Update completes successfully (§4.6): [newFirmwareDataGroup] plus
  /// [newFirmwareCheckDateTime] itself, since no check has happened since
  /// the install.
  static const newFirmwareStatusGroup = [
    newFirmwareCheckDateTime,
    ...newFirmwareDataGroup,
  ];
}

/// Attributes describing the Printer's *currently installed* Firmware.
/// FWUPDATE doesn't define these itself — they're from [PWG 5100.13] "IPP
/// Driver Replacement Extensions v2.0" — but Table 1 (§4.3) explicitly
/// cross-references them as the "Current Firmware Status Attribute"
/// counterpart to several `printer-new-firmware-*` attributes, so a
/// Printer implementing FWUPDATE needs them to make that before/after
/// comparison meaningful. `printer-firmware-info-uri` and
/// `printer-firmware-update-date-time` live in [FwStatusAttr] instead, since
/// FWUPDATE §6.3.1-6.3.2 define them directly (REQUIRED) rather than
/// merely referencing PWG 5100.13.
abstract final class CurrentFirmwareAttr {
  static const name = 'printer-firmware-name';
  static const patches = 'printer-firmware-patches';
  static const stringVersion = 'printer-firmware-string-version';
  static const version = 'printer-firmware-version';
}

/// Table 3 — keywords for the `delay-update-until` attribute (§6.1.1).
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

/// Table 4 — keywords for `printer-new-firmware-policy-configured` (§6.2.2).
abstract final class NewFirmwarePolicy {
  /// Printer automatically performs the Discovery, Acquisition,
  /// Validation, Installation and Activation phases.
  static const auto = 'auto';

  /// Printer automatically performs the Discovery phase, but waits for an
  /// Update-Printer-Firmware operation before the remaining phases.
  static const check = 'check';

  /// Printer performs every phase only in response to the operations
  /// defined in FWUPDATE §5 (i.e. only when a Client asks).
  static const directed = 'directed';

  /// Printer automatically performs the Discovery, Acquisition and
  /// Validation phases, but waits for an Update-Printer-Firmware operation
  /// before Installation and Activation.
  static const download = 'download';

  static const all = [auto, check, directed, download];
}

/// Table 5 — keywords for `printer-new-firmware-urgency` (§6.3.12).
abstract final class NewFirmwareUrgency {
  static const bugfix = 'bugfix';
  static const feature = 'feature';
  static const security = 'security';

  static const all = [bugfix, feature, security];
}

/// The `fwupdate` keyword this specification adds to `ipp-features-supported`
/// (§7.1).
const String ippFeatureFwupdate = 'fwupdate';
