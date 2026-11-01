import 'package:mrz/features/identity_scan/domain/scan_issue.dart';

/// What this app tells the user for each [ScanIssue]. The domain layer only
/// produces codes, so another host app can word them differently.
extension ScanIssueText on ScanIssue {
  String get title => switch (this) {
    ScanIssue.mrzNotFound => 'MRZ not found',
    ScanIssue.wrongDocument => 'Wrong document',
    ScanIssue.documentNotInFrame => 'Document not in frame',
    ScanIssue.imageNotClear => 'Image not clear',
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
  };

  /// This app lets the user look at the result anyway, except when it belongs
  /// to the wrong document or there is no document to read.
  bool get canContinue =>
      this != ScanIssue.wrongDocument && this != ScanIssue.documentNotInFrame;
}
