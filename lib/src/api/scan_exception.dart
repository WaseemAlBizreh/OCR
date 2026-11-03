/// Why a scan could not even start.
enum ScanFailureReason {
  /// The user did not allow camera access, and no image was captured.
  permissionDenied,

  /// No usable camera, or it failed to start, and no image was captured.
  cameraUnavailable,

  /// The host app is missing a setup step idlens cannot do for it: on iOS,
  /// `NSCameraUsageDescription` in `Info.plist`. The exception message says
  /// what to add.
  missingSetup,

  /// A file given to a `process*` method does not exist. A file that exists
  /// but is not a readable image does not throw: it gives a `failed` result.
  imageUnreadable,
}

/// Thrown only when there is nothing to return: no image exists to put in a
/// result. Anything that goes wrong after an image exists is reported through
/// the result's `status`, `issue` and `fieldsToCheck` instead.
class ScanException implements Exception {
  /// Creates an exception for [reason].
  const ScanException(this.reason, [this.message]);

  /// What went wrong.
  final ScanFailureReason reason;

  /// Extra detail for logs, when there is any.
  final String? message;

  @override
  String toString() =>
      'ScanException(${reason.name}${message == null ? '' : ': $message'})';
}
