import 'dart:io';

import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/api/passport_result.dart';
import 'package:idlens/src/api/civil_registry_result.dart';
import 'package:idlens/src/api/document_photo.dart';
import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/api/scan_review.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/api/scanned_image.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_latin_hybrid_recognizer.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_ocr_engine.dart'
    show ReaderUnavailableException;
import 'package:idlens/src/data/ocr/paddle/paddle_sudan_card_parser.dart';
import 'package:idlens/src/domain/document_framing.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/identity_scan_result.dart';
import 'package:idlens/src/domain/image_quality.dart';
import 'package:idlens/src/domain/mrz_validator.dart';
import 'package:idlens/src/domain/scan_deadline.dart';
import 'package:idlens/src/domain/scan_issue.dart';
import 'package:idlens/src/presentation/capture_crop.dart';
import 'package:idlens/src/services.dart';

/// What the clarity and framing checks say about one photo.
class PhotoCheck {
  const PhotoCheck({this.issue, this.quality, this.framing});

  /// [ScanIssue.imageNotClear], [ScanIssue.documentNotInFrame] or null.
  final ScanIssue? issue;
  final ImageQuality? quality;

  /// How the document sits in the photo, for `diagnostics`.
  final Map<String, dynamic>? framing;
}

/// The photos of one `process...` read: the files being read now, and which
/// of them idlens made. Shared by the crop stage, the read and the timeout
/// result, so every outcome lists the right files.
class PreparedPhotos {
  /// Starts with every photo's own file, read as it is.
  PreparedPhotos(Map<DocumentSide, DocumentPhoto> photos)
    : paths = {for (final e in photos.entries) e.key: e.value.file.path};

  /// What is read, by side. A cropped photo replaces its raw file here as
  /// soon as it is made.
  final Map<DocumentSide, String> paths;

  /// The sides whose path is a crop made by idlens, which the result owns and
  /// its `dispose()` deletes.
  final Set<DocumentSide> temporary = {};

  /// Per side, how the photo was cropped, for `diagnostics['photoCrop']`.
  final Map<String, dynamic> diagnostics = {};

  /// True once the time limit passed and the result was built, so a crop
  /// finishing after that must delete its own file.
  bool sealed = false;
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

  /// Clarity and framing of a photo of a [kind] document that has no MRZ to
  /// read (an ID front, a certificate), or of any whole photo.
  Future<PhotoCheck> checkPhoto(String path, DocumentKind kind) async {
    final frame = await _services.documentFrameChecker.measure(path);
    final coverage = _coverage(frame, kind);
    final quality = await _services.imageQualityChecker.checkWhole(
      path,
      documentCoverage: coverage.share,
    );
    final verdict = await _framing(path, kind, frame);
    final issue = ScanIssueResolver.resolve(
      recognizedFields: 0,
      imageIssue: quality?.problem,
      cutOff: verdict.cutOff,
    );
    return PhotoCheck(
      issue: issue,
      quality: quality,
      framing: _framingJson(verdict, frame, coverage),
    );
  }

  static FrameCoverage _coverage(FrameMeasure? frame, DocumentKind kind) =>
      frame == null
      ? FrameCoverage.unknown
      : DocumentFraming.coverage(frame, aspectRatio: kind.aspectRatio);

  /// Whether the document runs past an edge of the photo: from the photo
  /// itself when it can tell, otherwise from printed text at the edges
  /// ([textSides] when the pipeline already counted them).
  Future<FrameVerdict> _framing(
    String path,
    DocumentKind kind,
    FrameMeasure? frame, {
    int? textSides,
  }) async {
    final fromPhoto = frame == null
        ? null
        : DocumentFraming.fromPhoto(frame, aspectRatio: kind.aspectRatio);
    return fromPhoto ??
        DocumentFraming.fromText(
          textSides ?? await _services.frameEdgeChecker.touchedSides(path),
        );
  }

  static Map<String, dynamic> _framingJson(
    FrameVerdict verdict,
    FrameMeasure? frame,
    FrameCoverage coverage,
  ) => {
    ...verdict.toJson(),
    'coverage': coverage.toJson(),
    if (frame != null) 'measure': frame.toJson(),
  };

  /// What was captured before the user stopped: nothing was read.
  ScanOutcome incomplete(
    DocumentKind kind,
    Map<DocumentSide, String> paths, {
    Set<DocumentSide> temporary = const {},
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

  /// With a [timeout], a read still running when it passes returns `failed`
  /// with [ScanIssue.timedOut] and the images; the work left is skipped.
  Future<IdCardResult> idCard(
    Map<DocumentSide, String> paths, {
    Set<DocumentSide> temporary = const {},
    PhotoCheck? frontCheck,
    Duration? timeout,
  }) => ScanDeadline.run(
    timeout,
    () => _idCard(paths, temporary: temporary, frontCheck: frontCheck),
    () => IdCardResult(
      status: ScanStatus.failed,
      issue: ScanIssue.timedOut,
      images: _images(DocumentKind.sudanId, paths, temporary),
      diagnostics: _timedOutAfter(timeout!),
      scannedAt: DateTime.now(),
    ),
  );

  Future<IdCardResult> _idCard(
    Map<DocumentSide, String> paths, {
    required Set<DocumentSide> temporary,
    PhotoCheck? frontCheck,
    Map<String, dynamic> extraDiagnostics = const {},
  }) async {
    final images = _images(DocumentKind.sudanId, paths, temporary);
    final stopwatch = Stopwatch()..start();
    try {
      final front =
          frontCheck ??
          await checkPhoto(paths[DocumentSide.front]!, DocumentKind.sudanId);
      ScanDeadline.check();
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
      ScanDeadline.check();
      final judged = await _judge(
        result,
        DocumentKind.sudanId,
        paths[DocumentSide.back]!,
        frontIssue: front.issue,
      );
      return IdCardResult(
        status: judged.status,
        issue: judged.issue,
        issueSides: judged.issueSides,
        fieldsToCheck: judged.fieldsToCheck,
        images: images,
        diagnostics: {
          ..._diagnostics(result, judged.quality, judged.framing, stopwatch),
          ...extraDiagnostics,
          if (front.quality != null)
            'frontImageQuality': front.quality!.toJson(),
          if (front.framing != null) 'frontFraming': front.framing,
        },
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

  /// [timeout] works as for [idCard].
  Future<PassportResult> passport(
    String dataPagePath, {
    Set<DocumentSide> temporary = const {},
    Duration? timeout,
  }) => ScanDeadline.run(
    timeout,
    () => _passport(dataPagePath, temporary: temporary),
    () => PassportResult(
      status: ScanStatus.failed,
      issue: ScanIssue.timedOut,
      images: _images(DocumentKind.passport, {
        DocumentSide.dataPage: dataPagePath,
      }, temporary),
      diagnostics: _timedOutAfter(timeout!),
      scannedAt: DateTime.now(),
    ),
  );

  Future<PassportResult> _passport(
    String dataPagePath, {
    required Set<DocumentSide> temporary,
    Map<String, dynamic> extraDiagnostics = const {},
  }) async {
    final images = _images(DocumentKind.passport, {
      DocumentSide.dataPage: dataPagePath,
    }, temporary);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _services.passportScanService.scan(dataPagePath);
      ScanDeadline.check();
      final judged = await _judge(result, DocumentKind.passport, dataPagePath);
      return PassportResult(
        status: judged.status,
        issue: judged.issue,
        issueSides: judged.issueSides,
        fieldsToCheck: judged.fieldsToCheck,
        images: images,
        diagnostics: {
          ..._diagnostics(result, judged.quality, judged.framing, stopwatch),
          ...extraDiagnostics,
        },
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

  /// [timeout] works as for [idCard].
  ///
  /// With [flatten], the page is straightened to a flat A4 sheet before it is
  /// read, as the built-in camera does when it captures; the clarity and
  /// framing checks still look at [pagePath], and the result's image is
  /// [pagePath]. A photo with no clear page outline is read as it is.
  Future<CivilRegistryResult> civilRegistry(
    String pagePath, {
    Set<DocumentSide> temporary = const {},
    PhotoCheck? pageCheck,
    bool flatten = false,
    Duration? timeout,
  }) => ScanDeadline.run(
    timeout,
    () => _civilRegistry(
      pagePath,
      temporary: temporary,
      pageCheck: pageCheck,
      flatten: flatten,
    ),
    () => CivilRegistryResult(
      status: ScanStatus.failed,
      issue: ScanIssue.timedOut,
      images: _images(DocumentKind.civilRegistryCertificate, {
        DocumentSide.page: pagePath,
      }, temporary),
      diagnostics: _timedOutAfter(timeout!),
      scannedAt: DateTime.now(),
    ),
  );

  Future<CivilRegistryResult> _civilRegistry(
    String pagePath, {
    required Set<DocumentSide> temporary,
    PhotoCheck? pageCheck,
    required bool flatten,
    Map<String, dynamic> extraDiagnostics = const {},
  }) async {
    final images = _images(DocumentKind.civilRegistryCertificate, {
      DocumentSide.page: pagePath,
    }, temporary);
    final stopwatch = Stopwatch()..start();
    String? flatPath;
    try {
      const kind = DocumentKind.civilRegistryCertificate;
      final check = pageCheck ?? await checkPhoto(pagePath, kind);
      ScanDeadline.check();
      if (flatten) {
        flatPath = await _flatPage(pagePath);
        ScanDeadline.check();
      }
      final reading = await _services.civilRegistryScanService.scan(
        flatPath ?? pagePath,
      );
      ScanDeadline.check();
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
        issueSides: ScanReview.issueSides(
          issue,
          kind: kind,
          photos: {DocumentSide.page: check.issue},
        ),
        fieldsToCheck: fieldsToCheck,
        images: images,
        diagnostics: {
          'warnings': reading.warnings,
          'rawText': reading.rawText,
          'rawMlKit': reading.rawMlKit,
          ...extraDiagnostics,
          if (check.quality != null) 'imageQuality': check.quality!.toJson(),
          if (check.framing != null) 'framing': check.framing,
          if (flatten) 'pageFlattened': flatPath != null,
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
    } finally {
      if (flatPath != null) await _services.imageOps.deleteTemp(flatPath);
    }
  }

  /// A flat A4 copy of the certificate in [path], or null when no page
  /// outline is found or straightening fails, so the photo is read as it is.
  Future<String?> _flatPage(String path) async {
    try {
      return await _services.imageOps.cropPage(path, label: 'certificate');
    } catch (_) {
      return null;
    }
  }

  /// The issue for a read that threw: the text reader couldn't start or the
  /// time limit passed, which reading the same photos again may fix, or any
  /// other error.
  static ScanIssue _failureIssue(Object error) => switch (error) {
    ReaderUnavailableException() => ScanIssue.readerUnavailable,
    ScanTimedOutException() => ScanIssue.timedOut,
    _ => ScanIssue.processingFailed,
  };

  static Map<String, dynamic> _timedOutAfter(Duration timeout) => {
    'error': 'Timed out after ${timeout.inMilliseconds} ms',
    'timeoutMs': timeout.inMilliseconds,
  };

  /// The issue, fields to check and status of a document with an MRZ.
  /// [frontIssue] is the ID front's own photo problem, which comes first.
  Future<
    ({
      ScanIssue? issue,
      List<DocumentSide> issueSides,
      List<String> fieldsToCheck,
      ScanStatus status,
      ImageQuality? quality,
      Map<String, dynamic>? framing,
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
    FrameVerdict? verdict;
    Map<String, dynamic>? framing;
    if (!wrongDocument) {
      // Even a found MRZ can come from a dark or blurry photo whose other
      // fields are incomplete, or a cut-off one, so the photo is always
      // measured.
      final frame = await _services.documentFrameChecker.measure(mrzPagePath);
      final coverage = _coverage(frame, kind);
      quality = await _services.imageQualityChecker.check(
        mrzPagePath,
        kind,
        documentCoverage: coverage.share,
      );
      verdict = await _framing(
        mrzPagePath,
        kind,
        frame,
        textSides: result.frameTouchedSides,
      );
      framing = {
        ..._framingJson(verdict, frame, coverage),
        'mrzCut': result.mrz?.cutOff ?? false,
      };
    }
    final resolved = ScanIssueResolver.resolve(
      wrongDocument: wrongDocument,
      mrzMissing: result.mrz == null,
      recognizedFields: result.recognizedFieldCount,
      imageIssue: quality?.problem,
      // A cut MRZ line is proof on its own, even when the photo checks
      // can't tell.
      cutOff: (verdict?.cutOff ?? false) || (result.mrz?.cutOff ?? false),
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
      issueSides: ScanReview.issueSides(
        issue,
        kind: kind,
        photos: {
          if (kind == DocumentKind.sudanId) DocumentSide.front: frontIssue,
          kind.sides.last: resolved,
        },
      ),
      fieldsToCheck: fieldsToCheck,
      status: ScanReview.statusFor(
        issue: issue,
        readable: readable,
        fieldsToCheck: fieldsToCheck,
      ),
      quality: quality,
      framing: framing,
    );
  }

  Map<String, dynamic> _diagnostics(
    IdentityScanResult result,
    ImageQuality? quality,
    Map<String, dynamic>? framing,
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
    'framing': ?framing,
    'scanMs': stopwatch.elapsedMilliseconds,
  };

  /// Reads photos from the host app's own camera: each `camera` photo is
  /// first cropped the way idlens' own camera crops (see [cropAroundFrame]),
  /// then the read goes on as for any photo. The crop runs under [timeout]
  /// like the rest of the read.
  ///
  /// A photo that can't be cropped (the file exists but isn't an image) gives
  /// a `failed` result with `ScanIssue.processingFailed` and the images made
  /// so far, so a result exists whenever an image does.
  Future<IdCardResult> idCardFromPhotos(
    Map<DocumentSide, DocumentPhoto> photos, {
    Duration? timeout,
  }) {
    const kind = DocumentKind.sudanId;
    final prepared = PreparedPhotos(photos);
    return ScanDeadline.run(
      timeout,
      () async {
        final failure = await _prepare(photos, prepared);
        if (failure != null) {
          return IdCardResult(
            status: ScanStatus.failed,
            issue: ScanIssue.processingFailed,
            images: _images(kind, prepared.paths, prepared.temporary),
            diagnostics: {'error': failure},
            scannedAt: DateTime.now(),
          );
        }
        return _idCard(
          prepared.paths,
          temporary: prepared.temporary,
          extraDiagnostics: {'photoCrop': prepared.diagnostics},
        );
      },
      () {
        prepared.sealed = true;
        return IdCardResult(
          status: ScanStatus.failed,
          issue: ScanIssue.timedOut,
          images: _images(kind, prepared.paths, prepared.temporary),
          diagnostics: _timedOutAfter(timeout!),
          scannedAt: DateTime.now(),
        );
      },
    );
  }

  /// As [idCardFromPhotos], for a passport's data page.
  Future<PassportResult> passportFromPhoto(
    DocumentPhoto photo, {
    Duration? timeout,
  }) {
    const kind = DocumentKind.passport;
    const side = DocumentSide.dataPage;
    final photos = {side: photo};
    final prepared = PreparedPhotos(photos);
    return ScanDeadline.run(
      timeout,
      () async {
        final failure = await _prepare(photos, prepared);
        if (failure != null) {
          return PassportResult(
            status: ScanStatus.failed,
            issue: ScanIssue.processingFailed,
            images: _images(kind, prepared.paths, prepared.temporary),
            diagnostics: {'error': failure},
            scannedAt: DateTime.now(),
          );
        }
        return _passport(
          prepared.paths[side]!,
          temporary: prepared.temporary,
          extraDiagnostics: {'photoCrop': prepared.diagnostics},
        );
      },
      () {
        prepared.sealed = true;
        return PassportResult(
          status: ScanStatus.failed,
          issue: ScanIssue.timedOut,
          images: _images(kind, prepared.paths, prepared.temporary),
          diagnostics: _timedOutAfter(timeout!),
          scannedAt: DateTime.now(),
        );
      },
    );
  }

  /// As [idCardFromPhotos], for a certificate page. A flat copy of the page
  /// is read, as for [civilRegistry] with `flatten`.
  Future<CivilRegistryResult> civilRegistryFromPhoto(
    DocumentPhoto photo, {
    Duration? timeout,
  }) {
    const kind = DocumentKind.civilRegistryCertificate;
    const side = DocumentSide.page;
    final photos = {side: photo};
    final prepared = PreparedPhotos(photos);
    return ScanDeadline.run(
      timeout,
      () async {
        final failure = await _prepare(photos, prepared);
        if (failure != null) {
          return CivilRegistryResult(
            status: ScanStatus.failed,
            issue: ScanIssue.processingFailed,
            images: _images(kind, prepared.paths, prepared.temporary),
            diagnostics: {'error': failure},
            scannedAt: DateTime.now(),
          );
        }
        return _civilRegistry(
          prepared.paths[side]!,
          temporary: prepared.temporary,
          flatten: true,
          extraDiagnostics: {'photoCrop': prepared.diagnostics},
        );
      },
      () {
        prepared.sealed = true;
        return CivilRegistryResult(
          status: ScanStatus.failed,
          issue: ScanIssue.timedOut,
          images: _images(kind, prepared.paths, prepared.temporary),
          diagnostics: _timedOutAfter(timeout!),
          scannedAt: DateTime.now(),
        );
      },
    );
  }

  /// Crops the camera photos; returns what went wrong, or null. A time limit
  /// passing is not a failure of the photo and is rethrown.
  Future<String?> _prepare(
    Map<DocumentSide, DocumentPhoto> photos,
    PreparedPhotos prepared,
  ) async {
    try {
      await _cropCameraPhotos(photos, prepared);
      return null;
    } on ScanTimedOutException {
      rethrow;
    } catch (error) {
      return '$error';
    }
  }

  Future<void> _cropCameraPhotos(
    Map<DocumentSide, DocumentPhoto> photos,
    PreparedPhotos prepared,
  ) async {
    for (final MapEntry(key: side, value: photo) in photos.entries) {
      if (!photo.isCamera) continue;
      final path = await cropAroundFrame(
        photo.file.path,
        photo.frame,
        viewAspect: photo.viewAspect,
        label: 'process_${side.name}',
        imageOps: _services.imageOps,
      );
      if (prepared.sealed) {
        // The time limit passed while cropping: the result was built without
        // this file, so nothing else would delete it.
        await _services.imageOps.deleteTemp(path);
        throw const ScanTimedOutException();
      }
      prepared.paths[side] = path;
      prepared.temporary.add(side);
      prepared.diagnostics[side.name] = {
        'camera': true,
        'marginClipped': photo.frame.marginClipped,
      };
      ScanDeadline.check();
    }
  }

  static List<ScannedImage> _images(
    DocumentKind kind,
    Map<DocumentSide, String> paths,
    Set<DocumentSide> temporary,
  ) => [
    for (final side in kind.sides)
      if (paths[side] != null)
        ScannedImage(
          side: side,
          file: File(paths[side]!),
          isTemporary: temporary.contains(side),
        ),
  ];
}
