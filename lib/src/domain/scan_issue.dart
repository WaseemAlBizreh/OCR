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

  /// The page is in the frame, but what that page must hold was not found:
  /// the MRZ on a back or passport page, the required fields on an ID front or
  /// a certificate. Often the wrong side was photographed (the front twice, or
  /// the back twice), or the MRZ band is outside the frame. On a back or
  /// passport page it is reported even when the photo is also unclear; on an
  /// ID front or a certificate the photo is clear.
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
  /// photo (see `DocumentFraming`). [mrzPage] is true for a page read for its
  /// MRZ (an ID back, a passport).
  ///
  /// First match wins, and a document out of the frame always comes first,
  /// because nothing read from a partial photo can be trusted, a wrong
  /// document included:
  /// - every page: not in frame, then wrong document;
  /// - a page without an MRZ (ID front, certificate): then an unclear photo,
  ///   then missing content;
  /// - an [mrzPage]: then missing content (the MRZ), then an unclear photo.
  static ScanIssue? resolve({
    bool wrongDocument = false,
    bool contentMissing = false,
    ScanIssue? imageIssue,
    bool cutOff = false,
    bool mrzPage = false,
  }) {
    // A document far from the frame is also dark or blurry, but that is not
    // the real cause.
    if (imageIssue == ScanIssue.documentNotInFrame || cutOff) {
      return ScanIssue.documentNotInFrame;
    }
    if (wrongDocument) return ScanIssue.wrongDocument;
    if (mrzPage && contentMissing) return ScanIssue.contentNotFound;
    return imageIssue ?? (contentMissing ? ScanIssue.contentNotFound : null);
  }
}
