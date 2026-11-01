import 'dart:io';

import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/api/scanned_image.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_data.dart';
import 'package:idlens/src/domain/scan_issue.dart';

/// What every scan returns, whatever the document.
///
/// A result is returned as soon as one image was captured, even when reading
/// failed: [images] is then still filled, so an app may ignore [issues] and
/// upload the pictures. Fields that could not be read are null.
abstract class ScanOutcome {
  /// Creates an outcome. Results are built by idlens; apps read them.
  const ScanOutcome({
    required this.status,
    required this.documentKind,
    this.issues = const [],
    this.warnings = const [],
    this.images = const [],
    this.diagnostics = const {},
    required this.scannedAt,
  });

  /// How far the result can be trusted.
  final ScanStatus status;

  /// The document that was scanned.
  final DocumentKind documentKind;

  /// Why the scan cannot be fully trusted; empty when nothing was found wrong.
  final List<ScanIssue> issues;

  /// Human-readable detail for [issues], such as which printed value disagrees
  /// with the MRZ. English text meant for logs, not for end users.
  final List<String> warnings;

  /// The captured pages, in document order. Never empty on a returned result.
  final List<ScannedImage> images;

  /// Debug data: raw OCR text, MRZ read attempts, photo measurements, timing.
  /// Its content is not part of the stable API.
  final Map<String, dynamic> diagnostics;

  /// When the scan finished.
  final DateTime scannedAt;

  /// True when [status] is [ScanStatus.verified].
  bool get isVerified => status == ScanStatus.verified;

  /// The image for [side], or null when that page was not captured.
  ScannedImage? imageFor(DocumentSide side) {
    for (final image in images) {
      if (image.side == side) return image;
    }
    return null;
  }

  /// The fields that were read, keyed by name, for [toJson].
  Map<String, dynamic> get fields;

  /// The MRZ, for documents that have one and when it was found.
  MrzData? get mrz => null;

  /// Everything as JSON: status, issues, fields, MRZ, image paths and
  /// diagnostics. Image content is not included; use [ScannedImage.bytes].
  Map<String, dynamic> toJson() => {
    'documentKind': documentKind.name,
    'status': status.name,
    'issues': [for (final issue in issues) issue.name],
    'warnings': warnings,
    'fields': fields,
    if (mrz != null) 'mrz': mrz!.toJson(),
    'images': [for (final image in images) image.toJson()],
    'diagnostics': diagnostics,
    'scannedAt': scannedAt.toIso8601String(),
  };

  /// Deletes the image files idlens created in the temporary folder. Call it
  /// once the images are uploaded or stored. Files the app passed to a
  /// `process*` method are left alone.
  Future<void> dispose() async {
    for (final image in images) {
      if (!image.isTemporary) continue;
      try {
        if (await image.file.exists()) await image.file.delete();
      } on FileSystemException {
        // Already gone or locked: nothing useful to do about a temp file.
      }
    }
  }

  /// Picks the status for the findings of a scan.
  static ScanStatus statusFor({
    required List<ScanIssue> issues,
    required List<String> warnings,
    bool incomplete = false,
  }) {
    if (incomplete) return ScanStatus.incomplete;
    if (issues.any(_unreadable.contains)) return ScanStatus.failed;
    if (issues.isNotEmpty || warnings.isNotEmpty) return ScanStatus.needsReview;
    return ScanStatus.verified;
  }

  static const _unreadable = {
    ScanIssue.mrzNotFound,
    ScanIssue.wrongDocument,
    ScanIssue.documentNotInFrame,
    ScanIssue.processingFailed,
  };
}

/// Parses `yyyy-MM-dd` or `yyyy/MM/dd` into a date, or null when the text is
/// missing or not a real calendar date.
DateTime? parseScanDate(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  // DateTime rolls 31 Feb over to March, which would hide a misread date.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}
