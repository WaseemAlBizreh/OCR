/// Why a scan cannot be trusted. Codes only: the host app decides what to tell
/// the user, whether to let them continue, and in which language.
enum ScanIssue {
  /// No MRZ could be read from the image.
  mrzNotFound,

  /// An MRZ was read, but it belongs to another kind of document than the one
  /// being scanned (a passport shown for an ID card, or the reverse).
  wrongDocument,

  /// The document is not fully inside the frame: missing, too far away, or
  /// too close so that it is cut off.
  documentNotInFrame,

  /// The photo is not clear enough to read reliably: too dark, blurry or with
  /// glare on the document.
  imageNotClear,

  /// The MRZ was read but at least one of its check digits failed, so some of
  /// its values may be misread. `MrzData.checks` says which ones.
  mrzCheckDigitsFailed,

  /// Reading the images failed unexpectedly. The images are still returned.
  processingFailed,
}

/// Picks the one [ScanIssue] to report for a scan.
class ScanIssueResolver {
  ScanIssueResolver._();

  /// With fewer recognised fields than this (and no MRZ) nothing readable was
  /// in the frame.
  static const minFieldsInFrame = 2;

  /// Printed text running up to this many edges of the photo means the
  /// document is cut off.
  static const cutOffSides = 2;

  /// [mrzIssue] is the MRZ validator's code, [recognizedFields] how many
  /// printed fields were read, and [imageIssue] the photo-quality code (which
  /// can itself be [ScanIssue.documentNotInFrame] when the document is small
  /// in the frame) and [frameTouchedSides] the edges text runs up to.
  static ScanIssue? resolve({
    required ScanIssue? mrzIssue,
    required int recognizedFields,
    ScanIssue? imageIssue,
    int frameTouchedSides = 0,
  }) {
    if (mrzIssue == ScanIssue.wrongDocument) return mrzIssue;
    // A document far from the frame is also dark or blurry, but that is not
    // the real cause.
    if (imageIssue == ScanIssue.documentNotInFrame ||
        frameTouchedSides >= cutOffSides) {
      return ScanIssue.documentNotInFrame;
    }
    if (mrzIssue == ScanIssue.mrzNotFound &&
        recognizedFields < minFieldsInFrame) {
      return ScanIssue.documentNotInFrame;
    }
    return imageIssue ?? mrzIssue;
  }
}
