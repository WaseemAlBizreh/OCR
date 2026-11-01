import 'dart:io';

import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/api/passport_result.dart';
import 'package:idlens/src/api/civil_registry_result.dart';
import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/api/scanned_image.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_latin_hybrid_recognizer.dart';
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
/// It never throws for a problem with the document: those become `issues` on
/// a result that still carries the images.
class ScanRunner {
  ScanRunner([IdLensServices? services])
    : _services = services ?? IdLensServices.instance;

  static const _paddleParser = PaddleSudanCardParser();
  static const _mrzValidator = MrzValidator();

  final IdLensServices _services;

  /// Clarity and framing of a photo that has no MRZ to read (an ID front, a
  /// certificate), or of any whole photo.
  Future<PhotoCheck> checkPhoto(String path) async {
    final quality = _services.imageQualityChecker.checkWhole(path);
    final touched = await _services.frameEdgeChecker.touchedSides(path);
    final issue = ScanIssueResolver.resolve(
      mrzIssue: null,
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
        extraIssue: front.issue,
      );
      return IdCardResult(
        status: judged.status,
        issues: judged.issues,
        warnings: result.warnings,
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
        issues: const [ScanIssue.processingFailed],
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
        issues: judged.issues,
        warnings: result.warnings,
        images: images,
        diagnostics: _diagnostics(result, judged.quality, null, stopwatch),
        scannedAt: result.scannedAt,
        fields: result.identity,
        mrz: result.mrz,
      );
    } catch (error) {
      return PassportResult(
        status: ScanStatus.failed,
        issues: const [ScanIssue.processingFailed],
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
      final issues = [if (check.issue != null) check.issue!];
      return CivilRegistryResult(
        status: ScanOutcome.statusFor(
          issues: issues,
          warnings: reading.warnings,
        ),
        issues: issues,
        warnings: reading.warnings,
        images: images,
        diagnostics: {
          'rawText': reading.rawText,
          'rawMlKit': reading.rawMlKit,
          if (check.quality != null) 'imageQuality': check.quality!.toJson(),
          'scanMs': stopwatch.elapsedMilliseconds,
        },
        scannedAt: reading.scannedAt,
        fields: reading.fields,
        confidence: reading.confidence,
      );
    } catch (error) {
      return CivilRegistryResult(
        status: ScanStatus.failed,
        issues: const [ScanIssue.processingFailed],
        images: images,
        diagnostics: {'error': '$error'},
        scannedAt: DateTime.now(),
      );
    }
  }

  /// MRZ verdict, photo quality and the one resolved framing/clarity issue
  /// for a document with an MRZ.
  Future<({List<ScanIssue> issues, ScanStatus status, ImageQuality? quality})>
  _judge(
    IdentityScanResult result,
    DocumentKind kind,
    String mrzPagePath, {
    ScanIssue? extraIssue,
  }) async {
    final mrzIssue = _mrzValidator.validate(result.mrz, kind);
    ImageQuality? quality;
    if (mrzIssue != ScanIssue.wrongDocument) {
      // Even a found MRZ can come from a dark or blurry photo whose other
      // fields are incomplete, so the photo is always measured.
      quality = await _services.imageQualityChecker.check(mrzPagePath, kind);
    }
    final resolved = ScanIssueResolver.resolve(
      mrzIssue: mrzIssue,
      recognizedFields: result.recognizedFieldCount,
      imageIssue: quality?.problem,
      frameTouchedSides: result.frameTouchedSides ?? 0,
    );
    final issues = <ScanIssue>{
      ?extraIssue,
      ?resolved,
      if (result.mrz != null && !result.mrz!.isValid)
        ScanIssue.mrzCheckDigitsFailed,
    }.toList();
    return (
      issues: issues,
      status: ScanOutcome.statusFor(issues: issues, warnings: result.warnings),
      quality: quality,
    );
  }

  Map<String, dynamic> _diagnostics(
    IdentityScanResult result,
    ImageQuality? quality,
    ImageQuality? frontQuality,
    Stopwatch stopwatch,
  ) => {
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
