import 'dart:convert';
import 'dart:io';

import 'package:idlens/src/api/scan_review.dart';
import 'package:idlens/src/data/mrz/mrz_parser.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/domain/document_framing.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/image_quality.dart';
import 'package:idlens/src/domain/mrz_data.dart';
import 'package:idlens/src/domain/mrz_validator.dart';
import 'package:idlens/src/domain/scan_issue.dart';
import 'package:idlens/src/domain/validation_limits.dart';

/// Replays a stored scan result through the domain decision code, using only
/// the measurements saved in its `diagnostics`. No OpenCV, no OCR: what the
/// photo checks measured is taken as given, and every decision made from it
/// (framing, distance, clarity, issue, status, issueSides) is made again by
/// the code in this checkout.
///
/// It mirrors `ScanRunner.checkPhoto`, `ScanRunner._judge` and
/// `ScanRunner._civilRegistry`. Keep it in step with them.

/// The folders under `test/fixtures/scans/`.
const documentKinds = {
  'idFront': (DocumentKind.sudanId, DocumentSide.front),
  'idBack': (DocumentKind.sudanId, DocumentSide.back),
  'passport': (DocumentKind.passport, DocumentSide.dataPage),
  'certificate': (DocumentKind.civilRegistryCertificate, DocumentSide.page),
};

/// The labels a person can give, and the issue each one expects.
const labels = {
  'good': null,
  'cut': ScanIssue.documentNotInFrame,
  'far': ScanIssue.documentNotInFrame,
  'blurry': ScanIssue.imageNotClear,
  'dark': ScanIssue.imageNotClear,
  'glare': ScanIssue.imageNotClear,
  'wrongDocument': ScanIssue.wrongDocument,

  /// The other side was photographed for this page (an ID front shot as the
  /// back, or the back twice): the page lacks what it must hold.
  'wrongSide': ScanIssue.contentNotFound,
};

class ScanFixture {
  ScanFixture({
    required this.folder,
    required this.label,
    required this.name,
    required this.result,
    required this.meta,
  });

  final String folder;
  final String label;
  final String name;
  final Map<String, dynamic> result;
  final Map<String, dynamic> meta;

  DocumentKind get kind => documentKinds[folder]!.$1;
  DocumentSide get side => documentKinds[folder]!.$2;
  String get id => '$folder/$label/$name';
  bool get unsure => meta['label_confidence'] == 'unsure';
  Map<String, dynamic> get diagnostics =>
      (result['diagnostics'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Every `<kind>/<label>/<name>.json` under [root], sorted.
  static List<ScanFixture> loadAll(String root) {
    final dir = Directory(root);
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) => f.path.endsWith('.json') && !f.path.endsWith('.meta.json'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return [for (final file in files) _load(file, dir.path)];
  }

  static ScanFixture _load(File file, String root) {
    final parts = file.path
        .substring(root.length)
        .split(Platform.pathSeparator)
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length != 3) {
      throw FormatException(
        'Expected <documentKind>/<label>/<name>.json',
        file.path,
      );
    }
    final [folder, label, fileName] = parts;
    if (!documentKinds.containsKey(folder)) {
      throw FormatException('Unknown documentKind folder "$folder"', file.path);
    }
    if (!labels.containsKey(label)) {
      throw FormatException('Unknown label folder "$label"', file.path);
    }
    final name = fileName.substring(0, fileName.length - '.json'.length);
    final metaFile = File(
      file.path.replaceFirst(RegExp(r'\.json$'), '.meta.json'),
    );
    return ScanFixture(
      folder: folder,
      label: label,
      name: name,
      result: jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      meta: metaFile.existsSync()
          ? jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>
          : const {},
    );
  }
}

/// A measurement the decision needs but the stored result doesn't have.
class NotReplayable implements Exception {
  NotReplayable(this.missing);
  final String missing;
  @override
  String toString() => 'not replayable: missing $missing';
}

/// What the photo checks decided about one page.
class PageReplay {
  PageReplay({
    required this.verdict,
    required this.coverage,
    required this.quality,
    required this.measure,
    required this.storedFraming,
    required this.limits,
  });

  final FrameVerdict verdict;
  final FrameCoverage coverage;
  final ImageQuality quality;
  final FrameMeasure measure;
  final Map<String, dynamic> storedFraming;
  final ValidationLimits limits;

  /// What [quality] says with [limits].
  ScanIssue? get qualityIssue => quality.problemWith(limits);

  /// The issue `ScanRunner.checkPhoto` gives this page on its own.
  ScanIssue? get photoIssue => ScanIssueResolver.resolve(
    imageIssue: qualityIssue,
    cutOff: verdict.cutOff,
  );
}

/// The whole scan replayed, and the verdict for the fixture's own page.
class ScanReplay {
  ScanReplay({
    required this.fixture,
    required this.page,
    required this.pageIssue,
    required this.issue,
    required this.issueSides,
    required this.status,
    required this.decidedBy,
    this.mrzCut = false,
  });

  final ScanFixture fixture;

  /// The fixture's own page.
  final PageReplay page;

  /// The issue the fixture's page gets on its own (for an ID card side, the
  /// one that side contributes before the two are combined).
  final ScanIssue? pageIssue;

  /// The scan's combined result.
  final ScanIssue? issue;
  final List<DocumentSide> issueSides;
  final ScanStatus status;

  /// Which rule produced [pageIssue].
  final String decidedBy;
  final bool mrzCut;

  ScanIssue? get expected => labels[fixture.label];

  /// The label is met: the page has the expected issue, and the scan blames
  /// that page (or, when good, doesn't). A one-page document that is good
  /// must also not be `failed`.
  bool get matches {
    if (expected == null) {
      if (pageIssue != null) return false;
      if (issueSides.contains(fixture.side)) return false;
      if (fixture.kind.sides.length == 1 && status == ScanStatus.failed) {
        return false;
      }
      return true;
    }
    return pageIssue == expected && issueSides.contains(fixture.side);
  }

  bool get falseCutOff =>
      fixture.label == 'good' && pageIssue == ScanIssue.documentNotInFrame;

  bool get missedCut =>
      (fixture.label == 'cut' || fixture.label == 'far') &&
      pageIssue != ScanIssue.documentNotInFrame;
}

/// Replays [fixture]. Throws [NotReplayable] when a needed measurement is
/// missing.
ScanReplay replay(
  ScanFixture fixture, {
  ValidationLimits limits = ValidationLimits.standard,
}) {
  final kind = fixture.kind;
  final d = fixture.diagnostics;
  final storedKind = fixture.result['documentKind'];
  if (storedKind != kind.name) {
    throw FormatException(
      '${fixture.id}: documentKind is "$storedKind", folder says ${kind.name}',
    );
  }
  final fields =
      (fixture.result['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
  final storedFieldsToCheck = [
    for (final f in fixture.result['fieldsToCheck'] as List? ?? const []) '$f',
  ];

  switch (kind) {
    case DocumentKind.civilRegistryCertificate:
      final page = _page(d, 'framing', 'imageQuality', kind, limits);
      final check = page.photoIssue;
      final readable = ScanReview.isReadable(kind: kind, fields: fields);
      final issue = ScanIssueResolver.resolve(
        contentMissing: !readable,
        imageIssue: check,
      );
      return ScanReplay(
        fixture: fixture,
        page: page,
        pageIssue: issue,
        issue: issue,
        issueSides: ScanReview.issueSides(
          issue,
          kind: kind,
          photos: {DocumentSide.page: check},
        ),
        status: ScanReview.statusFor(
          issue: issue,
          readable: readable,
          // Not recomputed: `doubtfulFields` isn't stored, so the stored list
          // is the best there is. It never decides failed vs not failed.
          fieldsToCheck: storedFieldsToCheck,
        ),
        decidedBy: _decidedBy(page, issue, readable: readable),
      );

    case DocumentKind.passport || DocumentKind.sudanId:
      final mrz = _reparsedCut(_mrz(fixture.result['mrz']), d);
      final back = _page(d, 'framing', 'imageQuality', kind, limits);
      final mrzCut = mrz?.cutOff ?? false;
      final wrongDocument = const MrzValidator().isWrongDocument(mrz, kind);
      final resolved = ScanIssueResolver.resolve(
        wrongDocument: wrongDocument,
        contentMissing: mrz == null,
        mrzPage: true,
        imageIssue: back.qualityIssue,
        cutOff: back.verdict.cutOff || mrzCut,
      );
      PageReplay? front;
      ScanIssue? frontProblem;
      if (kind == DocumentKind.sudanId) {
        front = _page(d, 'frontFraming', 'frontImageQuality', kind, limits);
        frontProblem =
            front.photoIssue ??
            (!ScanReview.hasRequiredContent(kind, fields)
                ? ScanIssue.contentNotFound
                : null);
      }
      final issue = ScanReview.worse(frontProblem, resolved);
      final readable = ScanReview.isReadable(
        kind: kind,
        fields: fields,
        mrz: mrz,
      );
      final isFront = fixture.side == DocumentSide.front;
      final page = isFront ? front! : back;
      final pageIssue = isFront ? frontProblem : resolved;
      return ScanReplay(
        fixture: fixture,
        page: page,
        pageIssue: pageIssue,
        issue: issue,
        issueSides: ScanReview.issueSides(
          issue,
          kind: kind,
          photos: {
            if (kind == DocumentKind.sudanId) DocumentSide.front: frontProblem,
            kind.sides.last: resolved,
          },
        ),
        status: ScanReview.statusFor(
          issue: issue,
          readable: readable,
          fieldsToCheck: storedFieldsToCheck,
        ),
        decidedBy: _decidedBy(
          page,
          pageIssue,
          readable: isFront
              ? ScanReview.hasRequiredContent(kind, fields)
              : mrz != null,
          mrzCut: !isFront && mrzCut && !back.verdict.cutOff,
          wrongDocument: !isFront && wrongDocument,
        ),
        mrzCut: mrzCut,
      );
  }
}

PageReplay _page(
  Map<String, dynamic> d,
  String framingKey,
  String qualityKey,
  DocumentKind kind,
  ValidationLimits limits,
) {
  final framing = (d[framingKey] as Map?)?.cast<String, dynamic>();
  if (framing == null) throw NotReplayable('diagnostics.$framingKey');
  final m = (framing['measure'] as Map?)?.cast<String, dynamic>();
  if (m == null) throw NotReplayable('diagnostics.$framingKey.measure');
  final q = (d[qualityKey] as Map?)?.cast<String, dynamic>();
  if (q == null) throw NotReplayable('diagnostics.$qualityKey');

  double number(Map<String, dynamic> map, String key, String path) {
    final v = map[key];
    if (v is! num) throw NotReplayable('$path.$key');
    return v.toDouble();
  }

  final measure = FrameMeasure(
    width: number(m, 'width', 'diagnostics.$framingKey.measure'),
    height: number(m, 'height', 'diagnostics.$framingKey.measure'),
    outline: switch (m['outline']) {
      final List<dynamic> points => [
        for (final p in points.cast<List<dynamic>>())
          (x: (p[0] as num).toDouble(), y: (p[1] as num).toDouble()),
      ],
      _ => null,
    },
    region: switch (m['region']) {
      final Map<dynamic, dynamic> r => _region(
        r.cast<String, dynamic>(),
        'diagnostics.$framingKey.measure.region',
      ),
      _ => null,
    },
  );
  final aspect = kind.aspectRatio;
  final coverage = DocumentFraming.coverage(
    measure,
    aspectRatio: aspect,
    limits: limits,
  );
  final quality = ImageQuality(
    sharpness: number(q, 'sharpness', 'diagnostics.$qualityKey'),
    brightness: number(q, 'brightness', 'diagnostics.$qualityKey'),
    glareShare: number(q, 'glareShare', 'diagnostics.$qualityKey'),
    documentCoverage: coverage.share,
  );
  final fromPhoto = DocumentFraming.fromPhoto(
    measure,
    aspectRatio: aspect,
    limits: limits,
  );
  final FrameVerdict verdict;
  if (fromPhoto != null) {
    verdict = fromPhoto;
  } else if (framing['method'] == 'text' && framing['cutEdges'] is num) {
    // The stored verdict was from printed text, so cutEdges is the number of
    // edges text ran up to (clamped to 4, as fromText does again).
    verdict = DocumentFraming.fromText((framing['cutEdges'] as num).toInt());
  } else {
    // The photo can't tell now, but it could when the scan ran, so the
    // printed-text fallback was never measured.
    throw NotReplayable(
      'diagnostics.$framingKey.textTouchedSides (the replayed photo checks '
      'cannot decide; on the device "${framing['method']}" did)',
    );
  }
  return PageReplay(
    verdict: verdict,
    coverage: coverage,
    quality: quality,
    measure: measure,
    storedFraming: framing,
    limits: limits,
  );
}

FrameRegion _region(Map<String, dynamic> r, String path) {
  final box = r['box'];
  final contact = r['contact'];
  if (r['share'] is! num) throw NotReplayable('$path.share');
  if (box is! List || box.length != 4) throw NotReplayable('$path.box');
  if (contact is! List || contact.length != 4) {
    throw NotReplayable('$path.contact');
  }
  final b = [for (final v in box) (v as num).toDouble()];
  return FrameRegion(
    share: (r['share'] as num).toDouble(),
    left: b[0],
    top: b[1],
    right: b[2],
    bottom: b[3],
    contact: [for (final v in contact) (v as num).toDouble()],
  );
}

/// The MRZ as stored by `MrzData.toJson`, or null when none was read.
MrzData? _mrz(Object? json) {
  if (json is! Map) return null;
  final m = json.cast<String, dynamic>();
  String s(String key) => '${m[key] ?? ''}';
  return MrzData(
    format: MrzFormat.values.byName(s('format').toLowerCase()),
    lines: [for (final l in m['lines'] as List? ?? const []) '$l'],
    documentCode: s('documentCode'),
    issuingCountry: s('issuingCountry'),
    documentNumber: s('documentNumber'),
    dateOfBirth: s('dateOfBirth'),
    sex: s('sex'),
    expiryDate: s('expiryDate'),
    nationality: s('nationality'),
    surname: s('surname'),
    givenNames: s('givenNames'),
    optionalData: s('optionalData'),
    checks: {
      for (final e in (m['checks'] as Map? ?? const {}).entries)
        '${e.key}': e.value == true,
    },
    cutOff: m['cutOff'] == true,
  );
}

/// [stored] with its `cutOff` decided again by this checkout's [MrzParser],
/// from the ML Kit reads kept in `diagnostics.mrzAttempts`, chosen the way
/// `MrzReader.read` chooses (most check digits passing, stopping at the first
/// valid read). Only when that lands on the same lines the device stored;
/// otherwise (Paddle reads, or a read this replay can't reproduce) the stored
/// value is kept.
MrzData? _reparsedCut(MrzData? stored, Map<String, dynamic> d) {
  if (stored == null) return null;
  final attempts = d['mrzAttempts'];
  if (attempts is! List || attempts.isEmpty) return stored;
  final parser = MrzParser();
  MrzData? best;
  for (final a in attempts.cast<Map<dynamic, dynamic>>()) {
    final source = '${a['source']}';
    if (!source.startsWith('mlkit/')) return stored;
    final text = a['text'];
    final parsed = text is String
        ? parser.parseText(text, formats: MrzFormat.values)
        : null;
    if (parsed != null &&
        (best == null || parsed.passedChecks > best.passedChecks)) {
      best = parsed;
    }
    if (best?.isValid ?? false) break;
  }
  if (best == null || best.lines.join('\n') != stored.lines.join('\n')) {
    return stored;
  }
  return best.cutOff == stored.cutOff
      ? stored
      : (best.cutOff ? stored.withCut() : _withoutCut(stored));
}

MrzData _withoutCut(MrzData m) => MrzData(
  format: m.format,
  lines: m.lines,
  documentCode: m.documentCode,
  issuingCountry: m.issuingCountry,
  documentNumber: m.documentNumber,
  dateOfBirth: m.dateOfBirth,
  sex: m.sex,
  expiryDate: m.expiryDate,
  nationality: m.nationality,
  surname: m.surname,
  givenNames: m.givenNames,
  optionalData: m.optionalData,
  checks: m.checks,
);

String _decidedBy(
  PageReplay page,
  ScanIssue? issue, {
  required bool readable,
  bool mrzCut = false,
  bool wrongDocument = false,
}) {
  final q = page.quality;
  final v = page.verdict;
  final l = page.limits;
  if (issue == null) return 'none';
  if (issue == ScanIssue.documentNotInFrame) {
    if (q.documentCoverage < l.minDocumentCoverage) {
      return 'coverage<${l.minDocumentCoverage}';
    }
    if (v.cutOff) {
      final sides = v.cutSides?.map((s) => s.name).join('+') ?? '${v.cutEdges}';
      return 'cut($sides)';
    }
    if (mrzCut) return 'mrz.cutOff';
  }
  if (issue == ScanIssue.wrongDocument && wrongDocument) return 'mrzFormat';
  if (issue == ScanIssue.contentNotFound && !readable) return 'noContent';
  if (issue == ScanIssue.imageNotClear) {
    return [
      if (q.sharpness < l.minSharpness) 'sharpness',
      if (q.brightness < l.minBrightness) 'brightness',
      if (q.glareShare > l.maxGlareShare) 'glare',
    ].join('+');
  }
  return issue.name;
}

/// The numbers that drive the framing decision, for the table.
Map<String, String> keyNumbers(PageReplay page) {
  String f(double v, [int digits = 3]) => v.toStringAsFixed(digits);
  final m = page.measure;
  final r = m.region;
  final gaps = page.verdict.gaps;
  String? ratio;
  String? fill;
  if (page.verdict.method == FrameMethod.outline && m.outline != null) {
    final xs = m.outline!.map((p) => p.x);
    final ys = m.outline!.map((p) => p.y);
    final w =
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
    final h =
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
    ratio = f(w / h, 2);
  } else if (r != null) {
    final w = r.right - r.left;
    final h = r.bottom - r.top;
    ratio = f(w / h, 2);
    fill = f(r.share * m.width * m.height / (w * h), 2);
  }
  return {
    'gaps L,T,R,B': gaps == null ? '-' : gaps.map((g) => f(g)).join(','),
    'contact': r == null ? '-' : r.contact.map((c) => c.round()).join(','),
    'ratio': ratio ?? '-',
    'fill': fill ?? '-',
    'coverage': f(page.coverage.share, 2),
    'sharp': f(page.quality.sharpness, 0),
  };
}
