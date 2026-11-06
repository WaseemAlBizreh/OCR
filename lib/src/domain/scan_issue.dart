/// What is wrong with the photo or the document as a whole. Codes only: the
/// host app decides what to tell the user and in which language.
///
/// A doubt about a single value is never an issue: that field is listed in
/// `ScanOutcome.fieldsToCheck` instead.
enum ScanIssue {
  /// An MRZ was read, but it belongs to another kind of document than the one
  /// being scanned (a passport shown for an ID card, or the reverse), or a Sudan
  /// ID that is not Sudanese.
  wrongDocument,

  /// The document is not fully inside the frame: missing, too far away, or
  /// too close so that it is cut off.
  documentNotInFrame,

  /// The photo is not clear enough to read reliably: too dark, blurry or with
  /// glare.
  imageNotClear,

  /// The page is in the frame and the photo is clear, but what that page must
  /// hold was not found: the MRZ on a back or passport page, the required
  /// fields on an ID front or a certificate. Often the wrong side was
  /// photographed (the front twice, or the back twice), or the MRZ band is
  /// outside the frame.
  contentNotFound,

  /// Reading the images failed unexpectedly. The images are still returned.
  processingFailed,

  /// idlens couldn't start its text reader on this phone, for example with
  /// too little free storage. The photos are fine and are still returned.
  /// Reading the same photos again may work, with no retake needed.
  readerUnavailable,

  /// Reading took longer than the `timeout` the app passed, so idlens stopped
  /// it. The photos are fine and are still returned: reading them again may
  /// be quicker, with no retake needed.
  timedOut,
}

/// Picks the one [ScanIssue] to report for a photo.
class ScanIssueResolver {
  ScanIssueResolver._();

  /// [wrongDocument] is true when the MRZ belongs to another document,
  /// [contentMissing] when the page lacks what it must hold (see
  /// [ScanIssue.contentNotFound]), [imageIssue] the photo-quality code (which
  /// can itself be [ScanIssue.documentNotInFrame] when the document is small
  /// in the frame) and [cutOff] whether the document runs past an edge of the
  /// photo (see `DocumentFraming`).
  ///
  /// First match wins: a wrong document, then a document out of the frame,
  /// then an unclear photo (the first thing to retake), then missing content.
  static ScanIssue? resolve({
    bool wrongDocument = false,
    bool contentMissing = false,
    ScanIssue? imageIssue,
    bool cutOff = false,
  }) {
    if (wrongDocument) return ScanIssue.wrongDocument;
    // A document far from the frame is also dark or blurry, but that is not
    // the real cause.
    if (imageIssue == ScanIssue.documentNotInFrame || cutOff) {
      return ScanIssue.documentNotInFrame;
    }
    return imageIssue ?? (contentMissing ? ScanIssue.contentNotFound : null);
  }
}
