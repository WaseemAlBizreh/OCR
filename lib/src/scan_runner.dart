import 'dart:io';

import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/api/passport_result.dart';
import 'package:idlens/src/api/civil_registry_result.dart';
import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/api/scan_review.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/api/scanned_image.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_latin_hybrid_recognizer.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_ocr_engine.dart'
    show ReaderUnavailableException;
import 'package:idlens/src/data/ocr/paddle/paddle_sudan_card_parser.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/identity_scan_result.dart';
import 'package:idlens/src/domain/image_quality.dart';
import 'package:idlens/src/domain/mrz_validator.dart';
import 'package:idlens/src/domain/scan_issue.dart';
import 'package:idlens/src/services.dart';

/// What the clarity and framing checks say about one photo.
class PhotoCheck {
  const PhotoCheck({this.issue, this.quality});

  /// [ScanIssue.imageNotClear], [ScanIssue.documentNotInFrame] or null.
  final ScanIssue? issue;
  final ImageQuality? quality;
}

/// Runs a document through its pipeline and turns what comes out into a
/// [ScanOutcome]. The built-in flow and the headless `process*` methods both
/// go through here, so they cannot disagree.
///
/// It never throws for a problem with the document: those become the `issue`
/// and `fieldsToCheck` of a result that still carries the images. The rules
/// for both, and for the status, are in [ScanReview].
class ScanRunner {
  ScanRunner([IdLensServices? services])
    : _services = services ?? IdLensServices.instance;

  static const _paddleParser = PaddleSudanCardParser();
  static const _mrzValidator = MrzValidator();

  final IdLensServices _services;

  /// Clarity and framing of a photo that has no MRZ to read (an ID front, a
  /// certificate), or of any whole photo.
  Future<PhotoCheck> checkPhoto(String path) async {
    final quality = await _services.imageQualityChecker.checkWhole(path);
    final touched = await _services.frameEdgeChecker.touchedSides(path);
    final issue = ScanIssueResolver.resolve(
      recognizedFields: 0,
      imageIssue: quality?.problem,
      frameTouchedSides: touched,
    );
    return PhotoCheck(issue: issue, quality: quality);
  }

  /// What was captured before the user stopped: nothing was read.
  ScanOutcome incomplete(
    DocumentKind kind,
    Map<DocumentSide, String> paths, {
    bool temporary = true,
  }) {
    final images = _images(kind, paths, temporary);
    final now = DateTime.now();
    return switch (kind) {
      DocumentKind.sudanId => IdCardResult(
        status: ScanStatus.incomplete,
        images: images,
        scannedAt: now,
      ),
      DocumentKind.passport => PassportResult(
        status: ScanStatus.incomplete,
        images: images,
        scannedAt: now,
      ),
      DocumentKind.civilRegistryCertificate => CivilRegistryResult(
        status: ScanStatus.incomplete,
        images: images,
        scannedAt: now,
      ),
    };
  }

  Future<IdCardResult> idCard(
    Map<DocumentSide, String> paths, {
    bool temporary = false,
    PhotoCheck? frontCheck,
  }) async {
    final images = _images(DocumentKind.sudanId, paths, temporary);
    final stopwatch = Stopwatch()..start();
    try {
      final front = frontCheck ?? await checkPhoto(paths[DocumentSide.front]!);
      final result = await _services.identityScanService.scan(
        kind: DocumentKind.sudanId,
        imagePaths: paths,
        cardText: PaddleLatinHybridRecognizer(
          _services.paddleOcrEngine,
          _services.ocrEngine,
        ),
        parseFront: _paddleParser.parseFront,
        parseBack: _paddleParser.parseBack,
        includeRawText: true,
      );
      final judged = await _judge(
        result,
        DocumentKind.sudanId,
        paths[DocumentSide.back]!,
        frontIssue: front.issue,
      );
      return IdCardResult(
        status: judged.status,
        issue: judged.issue,
        fieldsToCheck: judged.fieldsToCheck,
        images: images,
        diagnostics: _diagnostics(
          result,
          judged.quality,
          front.quality,
          stopwatch,
        ),
        scannedAt: result.scannedAt,
        fields: result.identity,
        mrz: result.mrz,
      );
    } catch (error) {
      return IdCardResult(
        status: ScanStatus.failed,
        issue: _failureIssue(error),
        images: images,
        diagnostics: {'error': '$error'},
        scannedAt: DateTime.now(),
      );
    }
  }

  Future<PassportResult> passport(
    String dataPagePath, {
    bool temporary = false,
  }) async {
    final images = _images(DocumentKind.passport, {
      DocumentSide.dataPage: dataPagePath,
    }, temporary);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _services.passportScanService.scan(dataPagePath);
      final judged = await _judge(result, DocumentKind.passport, dataPagePath);
      return PassportResult(
        status: judged.status,
        issue: judged.issue,
        fieldsToCheck: judged.fieldsToCheck,
        images: images,
        diagnostics: _diagnostics(result, judged.quality, null, stopwatch),
        scannedAt: result.scannedAt,
        fields: result.identity,
        mrz: result.mrz,
      );
    } catch (error) {
      return PassportResult(
        status: ScanStatus.failed,
        issue: _failureIssue(error),
        images: images,
        diagnostics: {'error': '$error'},
        scannedAt: DateTime.now(),
      );
    }
  }

  Future<CivilRegistryResult> civilRegistry(
    String pagePath, {
    bool temporary = false,
    PhotoCheck? pageCheck,
  }) async {
    final images = _images(DocumentKind.civilRegistryCertificate, {
      DocumentSide.page: pagePath,
    }, temporary);
    final stopwatch = Stopwatch()..start();
    try {
      final check = pageCheck ?? await checkPhoto(pagePath);
      final reading = await _services.civilRegistryScanService.scan(pagePath);
      const kind = DocumentKind.civilRegistryCertificate;
      final readable = ScanReview.isReadable(
        kind: kind,
        fields: reading.fields,
      );
      final issue = ScanReview.issueFor(check.issue, readable: readable);
      final fieldsToCheck = ScanReview.fieldsToCheck(
        kind: kind,
        fields: reading.fields,
        doubtful: reading.doubtfulFields,
      );
      return CivilRegistryResult(
        status: ScanReview.statusFor(
          issue: issue,
          readable: readable,
          fieldsToCheck: fieldsToCheck,
        ),
        issue: issue,
        fieldsToCheck: fieldsToCheck,
        images: images,
        diagnostics: {
          'warnings': reading.warnings,
          'rawText': reading.rawText,
          'rawMlKit': reading.rawMlKit,
          if (check.quality != null) 'imageQuality': check.quality!.toJson(),
          'scanMs': stopwatch.elapsedMilliseconds,
        },
        scannedAt: reading.scannedAt,
        fields: reading.fields,
      );
    } catch (error) {
      return CivilRegistryResult(
        status: ScanStatus.failed,
        issue: _failureIssue(error),
        images: images,
        diagnostics: {'error': '$error'},
        scannedAt: DateTime.now(),
      );
    }
  }

  /// The issue for a read that threw: the text reader couldn't start, which
  /// reading the same photos again may fix, or any other error.
  static ScanIssue _failureIssue(Object error) =>
      error is ReaderUnavailableException
      ? ScanIssue.readerUnavailable
      : ScanIssue.processingFailed;

  /// The issue, fields to check and status of a document with an MRZ.
  /// [frontIssue] is the ID front's own photo problem, which comes first.
  Future<
    ({
      ScanIssue? issue,
      List<String> fieldsToCheck,
      ScanStatus status,
      ImageQuality? quality,
    })
  >
  _judge(
    IdentityScanResult result,
    DocumentKind kind,
    String mrzPagePath, {
    ScanIssue? frontIssue,
  }) async {
    final wrongDocument = _mrzValidator.isWrongDocument(result.mrz, kind);
    ImageQuality? quality;
    if (!wrongDocument) {
      // Even a found MRZ can come from a dark or blurry photo whose other
      // fields are incomplete, so the photo is always measured.
      quality = await _services.imageQualityChecker.check(mrzPagePath, kind);
    }
    final resolved = ScanIssueResolver.resolve(
      wrongDocument: wrongDocument,
      mrzMissing: result.mrz == null,
      recognizedFields: result.recognizedFieldCount,
      imageIssue: quality?.problem,
      frameTouchedSides: result.frameTouchedSides ?? 0,
    );
    final readable = ScanReview.isReadable(
      kind: kind,
      fields: result.identity,
      mrz: result.mrz,
    );
    final issue = ScanReview.issueFor(
      ScanReview.worse(frontIssue, resolved),
      readable: readable,
    );
    final fieldsToCheck = ScanReview.fieldsToCheck(
      kind: kind,
      fields: result.identity,
      doubtful: result.doubtfulFields,
      mrz: result.mrz,
    );
    return (
      issue: issue,
      fieldsToCheck: fieldsToCheck,
      status: ScanReview.statusFor(
        issue: issue,
        readable: readable,
        fieldsToCheck: fieldsToCheck,
      ),
      quality: quality,
    );
  }

  Map<String, dynamic> _diagnostics(
    IdentityScanResult result,
    ImageQuality? quality,
    ImageQuality? frontQuality,
    Stopwatch stopwatch,
  ) => {
    'warnings': result.warnings,
    if (result.frontFields != null) 'front': result.frontFields,
    if (result.backFields != null) 'back': result.backFields,
    if (result.dataPageFields != null) 'dataPage': result.dataPageFields,
    'mrzAttempts': result.mrzAttempts,
    if (result.rawText.isNotEmpty)
      'rawText': {for (final e in result.rawText.entries) e.key.name: e.value},
    if (quality != null) 'imageQuality': quality.toJson(),
    if (frontQuality != null) 'frontImageQuality': frontQuality.toJson(),
    'scanMs': stopwatch.elapsedMilliseconds,
  };

  static List<ScannedImage> _images(
    DocumentKind kind,
    Map<DocumentSide, String> paths,
    bool temporary,
  ) => [
    for (final side in kind.sides)
      if (paths[side] != null)
        ScannedImage(
          side: side,
          file: File(paths[side]!),
          isTemporary: temporary,
        ),
  ];
}
