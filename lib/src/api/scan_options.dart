/// Options shared by every `scan...` method. The `process...` methods take no
/// options object: they never open a screen, and take their own `timeout`.
class ScanOptions {
  /// Creates options. The defaults suit most apps.
  const ScanOptions({
    this.showTips = true,
    this.requireValidMrz = false,
    this.timeout,
  });

  /// Whether the built-in flow starts with its page of photo tips. When false
  /// the camera opens straight away.
  final bool showTips;

  /// Whether the built-in flow refuses to continue until the machine-readable
  /// zone (MRZ) is found and its check digits pass: the user can only retake.
  /// Off by default, so users may continue anyway and the app decides what to
  /// do with the `issue`. The `process...` methods never
  /// block.
  final bool requireValidMrz;

  /// How long the built-in flow may spend reading the photos, or null (the
  /// default) for no limit. A read still running then gives `failed` with
  /// `ScanIssue.timedOut`, and the user is offered to try again. The
  /// `process*` methods take their own `timeout` instead.
  final Duration? timeout;
}

/// Options for `IdLens.scanIdCard`.
class IdCardScanOptions extends ScanOptions {
  /// Creates options for an ID card scan.
  const IdCardScanOptions({
    super.showTips,
    super.requireValidMrz,
    super.timeout,
  });
}

/// Options for `IdLens.scanPassport`.
class PassportScanOptions extends ScanOptions {
  /// Creates options for a passport scan.
  const PassportScanOptions({
    super.showTips,
    super.requireValidMrz,
    super.timeout,
  });
}

/// Options for `IdLens.scanCivilRegistry`.
/// A certificate has no MRZ, so `requireValidMrz` has no effect.
class CivilRegistryScanOptions extends ScanOptions {
  /// Creates options for a civil registry certificate scan.
  const CivilRegistryScanOptions({super.showTips, super.timeout});
}
