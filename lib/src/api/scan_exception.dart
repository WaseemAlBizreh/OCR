/// Why a scan could not even start.
enum ScanFailureReason {
  /// The user did not allow camera access, and no image was captured.
  permissionDenied,

  /// No usable camera, or it failed to start, and no image was captured.
  cameraUnavailable,

  /// An image given to a `process*` method is missing or is not a readable
  /// image file.
  imageUnreadable,
}

/// Thrown only when there is nothing to return: no image exists to put in a
/// result. Anything that goes wrong after an image exists is reported through
/// the result's `status` and `issues` instead.
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
