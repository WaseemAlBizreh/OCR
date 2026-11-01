import 'package:idlens/src/domain/scan_issue.dart';

/// What this app tells the user for each [ScanIssue]. The domain layer only
/// produces codes, so another host app can word them differently.
extension ScanIssueText on ScanIssue {
  String get title => switch (this) {
    ScanIssue.mrzNotFound => 'MRZ not found',
    ScanIssue.wrongDocument => 'Wrong document',
    ScanIssue.documentNotInFrame => 'Document not in frame',
    ScanIssue.imageNotClear => 'Image not clear',
    ScanIssue.mrzCheckDigitsFailed => 'MRZ could not be verified',
    ScanIssue.processingFailed => 'Scan failed',
  };

  String get message => switch (this) {
    ScanIssue.mrzNotFound =>
      'No MRZ found. Make sure the machine-readable lines at the bottom of '
          'the document are inside the frame, then retake.',
    ScanIssue.wrongDocument =>
      'This is not the document you chose to scan. '
          'Scan the correct document and retake.',
    ScanIssue.documentNotInFrame =>
      'The whole document must be inside the box: not too far, not too close '
          'and not cut off at the edges. Fit it inside the box and retake.',
    ScanIssue.imageNotClear =>
      'The image is not clear. Use good light, avoid glare, hold steady and retake.',
    ScanIssue.mrzCheckDigitsFailed =>
      'The machine-readable lines were read, but their check digits do not '
          'match, so some values may be wrong. Retake with the MRZ sharp and '
          'fully inside the frame.',
    ScanIssue.processingFailed =>
      'The document could not be processed. Retake the photos and try again.',
  };

  /// Problems with the machine-readable zone itself. With `requireValidMrz`
  /// the built-in flow lets the user only retake after one of these.
  bool get isMrzProblem =>
      this == ScanIssue.mrzNotFound ||
      this == ScanIssue.wrongDocument ||
      this == ScanIssue.mrzCheckDigitsFailed;
}
