/// How far a scan can be trusted. Every status comes with the captured images,
/// so a result is always usable for upload.
enum ScanStatus {
  /// No issue, and nothing in `fieldsToCheck`. For documents with a
  /// machine-readable zone, its check digits all passed and the printed
  /// values agree with it. Optional fields that were not read are null.
  verified,

  /// The values were read, but the photo is not clear
  /// (`ScanIssue.imageNotClear`) or at least one field is in `fieldsToCheck`.
  needsReview,

  /// The document could not be read: it is the wrong document, is not in the
  /// frame, nothing identifying was read (no MRZ, or none of a certificate's
  /// required fields), or processing failed. `issue` says which. The images
  /// are still returned.
  failed,

  /// Capturing stopped before every page of the document was taken, so
  /// nothing was read. Only the images captured so far are returned.
  incomplete,
}
