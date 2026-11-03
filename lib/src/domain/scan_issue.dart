/// What is wrong with the photo or the document as a whole. Codes only: the
/// host app decides what to tell the user and in which language.
///
/// A doubt about a single value is never an issue: that field is listed in
/// `ScanOutcome.fieldsToCheck` instead.
enum ScanIssue {
  /// An MRZ was read, but it belongs to another kind of document than the one
  /// being scanned (a passport shown for an ID card, or the reverse).
  wrongDocument,

  /// The document is not fully inside the frame: missing, too far away, or
  /// too close so that it is cut off.
  documentNotInFrame,

  /// The photo is not clear enough to read reliably: too dark, blurry or with
  /// glare. Also given when the document is in the frame but its MRZ could
  /// not be read.
  imageNotClear,

  /// Reading the images failed unexpectedly. The images are still returned.
  processingFailed,

  /// idlens couldn't start its text reader on this phone, for example with
  /// too little free storage. The photos are fine and are still returned.
  /// Reading the same photos again may work, with no retake needed.
  readerUnavailable,
}

/// Picks the one [ScanIssue] to report for a photo.
class ScanIssueResolver {
  ScanIssueResolver._();

  /// With fewer recognised fields than this (and no MRZ) nothing readable was
  /// in the frame.
  static const minFieldsInFrame = 2;

  /// [wrongDocument] is true when the MRZ belongs to another document,
  /// [mrzMissing] when a document that has an MRZ showed none,
  /// [recognizedFields] how many printed fields were read, [imageIssue] the
  /// photo-quality code (which can itself be [ScanIssue.documentNotInFrame]
  /// when the document is small in the frame) and [cutOff] whether the
  /// document runs past an edge of the photo (see `DocumentFraming`).
  static ScanIssue? resolve({
    bool wrongDocument = false,
    bool mrzMissing = false,
    required int recognizedFields,
    ScanIssue? imageIssue,
    bool cutOff = false,
  }) {
    if (wrongDocument) return ScanIssue.wrongDocument;
    // A document far from the frame is also dark or blurry, but that is not
    // the real cause.
    if (imageIssue == ScanIssue.documentNotInFrame || cutOff) {
      return ScanIssue.documentNotInFrame;
    }
    if (mrzMissing && recognizedFields < minFieldsInFrame) {
      return ScanIssue.documentNotInFrame;
    }
    if (mrzMissing) return ScanIssue.imageNotClear;
    return imageIssue;
  }
}
