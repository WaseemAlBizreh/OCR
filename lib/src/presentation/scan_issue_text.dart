import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/scan_issue.dart';

/// What the built-in flow tells the user. The result only carries codes, so
/// another host app can word them differently.
class ScanNotice {
  const ScanNotice(this.title, this.message, {this.readAgain = false});

  final String title;
  final String message;

  /// The photos are fine, so the user is offered to read them again instead
  /// of retaking them.
  final bool readAgain;

  /// The notice for [issue]. [sides] are the pages to retake: they say which
  /// content was not found for [ScanIssue.contentNotFound].
  factory ScanNotice.forIssue(
    ScanIssue issue, {
    List<DocumentSide> sides = const [],
  }) => switch (issue) {
    ScanIssue.wrongDocument => const ScanNotice(
      'Wrong document',
      'This is not the document you chose to scan. '
          'Scan the correct document and retake.',
    ),
    ScanIssue.documentNotInFrame => const ScanNotice(
      'Document not in frame',
      'The whole document must be inside the box: not too far, not too close '
          'and not cut off at the edges. Fit it inside the box and retake.',
    ),
    ScanIssue.imageNotClear => const ScanNotice(
      'Image not clear',
      'The image is not clear. Use good light, avoid glare, hold steady and '
          'retake.',
    ),
    ScanIssue.contentNotFound =>
      sides.contains(DocumentSide.back) || sides.contains(DocumentSide.dataPage)
          ? _mrzNotFound
          : const ScanNotice(
              'Details not found',
              'The details of this page could not be found. Make sure it is '
                  'the right side of the document, fully inside the box, and '
                  'retake.',
            ),
    ScanIssue.processingFailed => const ScanNotice(
      'Scan failed',
      'The document could not be processed. Retake the photos and try again.',
    ),
    ScanIssue.readerUnavailable => const ScanNotice(
      "The scanner couldn't start",
      'Your photos are fine. Try again in a moment. If it keeps happening, '
          'free up some storage or restart the app.',
      readAgain: true,
    ),
    ScanIssue.timedOut => const ScanNotice(
      'Reading took too long',
      'Your photos are fine. Try again. If it keeps happening, close other '
          'apps or restart the phone.',
      readAgain: true,
    ),
  };

  static const _mrzNotFound = ScanNotice(
    'MRZ not found',
    'No MRZ found. Make sure the machine-readable lines at the bottom of the '
        'document are inside the frame, then retake.',
  );

  static const _mrzNotVerified = ScanNotice(
    'MRZ could not be verified',
    'The machine-readable lines were read, but their check digits do not '
        'match, so some values may be wrong. Retake with the MRZ sharp and '
        'fully inside the frame.',
  );

  /// The notice for a finished scan, or null when there is nothing to say.
  /// [alreadyShown] is the issue the user already saw for [shownSide]'s
  /// photo before reading. It is shown again when another page has a problem
  /// too.
  static ScanNotice? after(
    ScanOutcome outcome, {
    ScanIssue? alreadyShown,
    DocumentSide? shownSide,
  }) {
    final issue = outcome.issue;
    final otherSide = outcome.issueSides.any((side) => side != shownSide);
    if (issue != null && (issue != alreadyShown || otherSide)) {
      return ScanNotice.forIssue(issue, sides: outcome.issueSides);
    }
    // The MRZ was read but a check digit failed: the fields it covers are in
    // `fieldsToCheck`, which is what the flow's "retake" is for.
    final mrz = outcome.mrz;
    if (mrz != null && !mrz.isValid) {
      return _mrzNotVerified;
    }
    return null;
  }

  /// Whether the MRZ is missing, wrong or failed a check digit. With
  /// `requireValidMrz` the built-in flow then lets the user only retake.
  static bool hasMrzProblem(ScanOutcome outcome) =>
      outcome.documentKind.hasMrz &&
      (outcome.issue == ScanIssue.wrongDocument ||
          outcome.mrz == null ||
          !outcome.mrz!.isValid);
}
