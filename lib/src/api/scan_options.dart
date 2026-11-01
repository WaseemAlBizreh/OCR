/// Options shared by every scan.
class ScanOptions {
  /// Creates options. The defaults suit most apps.
  const ScanOptions({this.showTips = true, this.requireValidMrz = false});

  /// Whether the built-in flow starts with its page of photo tips. When false
  /// the camera opens straight away. Ignored by the `process*` methods.
  final bool showTips;

  /// Whether the built-in flow refuses to continue until the machine-readable
  /// zone (MRZ) is found and its check digits pass: the user can only retake.
  /// Off by default, so users may continue anyway and the app decides what to
  /// do with the `issues`. Ignored by the `process*` methods, which never
  /// block.
  final bool requireValidMrz;
}

/// Options for `IdLens.scanIdCard` and `IdLens.processIdCard`.
class IdCardScanOptions extends ScanOptions {
  /// Creates options for an ID card scan.
  const IdCardScanOptions({super.showTips, super.requireValidMrz});
}

/// Options for `IdLens.scanPassport` and `IdLens.processPassport`.
class PassportScanOptions extends ScanOptions {
  /// Creates options for a passport scan.
  const PassportScanOptions({super.showTips, super.requireValidMrz});
}

/// Options for `IdLens.scanCivilRegistry` and `IdLens.processCivilRegistry`.
/// A certificate has no MRZ, so `requireValidMrz` has no effect.
class CivilRegistryScanOptions extends ScanOptions {
  /// Creates options for a civil registry certificate scan.
  const CivilRegistryScanOptions({super.showTips});
}
