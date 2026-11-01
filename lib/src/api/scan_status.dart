/// How far a scan can be trusted. Every status comes with the captured images,
/// so a result is always usable for upload.
enum ScanStatus {
  /// Nothing was found wrong: for documents with a machine-readable zone, its
  /// check digits all passed, and the printed fields agree with it.
  verified,

  /// Fields were read, but something is off. See [ScanOutcome.issues] and
  /// [ScanOutcome.warnings]; some values may be missing or wrong.
  needsReview,

  /// The document could not be read: it is the wrong document, is not in the
  /// frame, has no readable MRZ, or processing failed. The images are still
  /// returned.
  failed,

  /// Capturing stopped before every page of the document was taken, so
  /// nothing was read. Only the images captured so far are returned.
  incomplete,
}
