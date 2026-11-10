// Calibrates the photo-check limits from the labelled real scans in
// test/fixtures/scans/. For each limit in ValidationLimits it sweeps a range
// of values, holding the others at today's values, replays every usable
// fixture, and prints per value: matches, false positives (good judged bad)
// and false negatives (bad judged good), the best range, and the measured
// values per label so a person can see the margin.
//
// It only reports; it never fails. Choose a limit from the middle of its best
// range, change the constant in lib/src/domain/, and record why in
// doc/internal/VALIDATION_RULES.md.
//
//   flutter test test/regression/calibrate_test.dart
//
// Skipped: labels marked "unsure" and fixtures measured before 0.4.0
// ("measuredBy": "pre-0.4.0" in the meta), whose measurements the current
// measurer can't produce.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/document_framing.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/validation_limits.dart';

import 'scan_replay.dart';

const fixturesRoot = 'test/fixtures/scans';

/// The swept range of each limit: from, to, step.
const sweeps = {
  'minDocumentCoverage': (0.30, 0.75, 0.01),
  'minSharpness': (0.0, 200.0, 5.0),
  'minBrightness': (40.0, 180.0, 5.0),
  'maxGlareShare': (0.02, 0.60, 0.02),
  'edgeMargin': (0.0, 0.06, 0.0025),
  'minContact': (0.10, 1.00, 0.05),
  'regionAspectTolerance': (0.05, 0.50, 0.025),
  'uprightRegionTolerance': (0.02, 0.40, 0.01),
  'aspectTolerance': (0.05, 0.50, 0.025),
};

/// Fixtures the calibration leaves out, and why.
String? skipReason(ScanFixture f) {
  if (f.unsure) return 'label unsure';
  if (f.meta['measuredBy'] == 'pre-0.4.0') return 'measured before 0.4.0';
  return null;
}

void main() {
  // The scans hold personal data and are kept out of git and pub.dev, so a
  // checkout without them skips this test instead of failing.
  if (!Directory(fixturesRoot).existsSync()) {
    test('$fixturesRoot is not present; skipped', () {}, skip: true);
    return;
  }
  test('calibration report', () {
    final all = ScanFixture.loadAll(fixturesRoot);
    final usable = <ScanFixture>[];
    final skipped = <String>[];
    for (final f in all) {
      final reason = skipReason(f);
      if (reason != null) {
        skipped.add('${f.id}: $reason');
        continue;
      }
      try {
        replay(f);
        usable.add(f);
      } on NotReplayable catch (e) {
        skipped.add('${f.id}: $e');
      }
    }
    stdout.write(report(usable, skipped));
  });
}

String report(List<ScanFixture> fixtures, List<String> skipped) {
  final out = StringBuffer()
    ..writeln()
    ..writeln(
      'idlens limit calibration: ${fixtures.length} fixtures, '
      '${skipped.length} skipped',
    );
  for (final s in skipped) {
    out.writeln('  skipped $s');
  }
  final baseline = _score(fixtures, ValidationLimits.standard);
  out
    ..writeln(
      'today\'s limits: ${baseline.matches}/${fixtures.length} match, '
      '${baseline.falsePositives.length} false positives, '
      '${baseline.falseNegatives.length} false negatives',
    )
    ..writeln(
      'FP: good judged bad. FN: bad judged good. n/r: the photo check cannot '
      'decide with that value and the text check was not stored (not a match).',
    );

  for (final entry in sweeps.entries) {
    final name = entry.key;
    final (from, to, step) = entry.value;
    final current = ValidationLimits.standard.toMap()[name]!;
    out
      ..writeln()
      ..writeln('== $name (today ${_n(current)}) ==');
    _measuredPerLabel(out, name, fixtures);

    final rows = <(double, _Score)>[];
    for (var i = 0; from + i * step <= to + step / 2; i++) {
      final value = _round(from + i * step);
      rows.add((
        value,
        _score(fixtures, ValidationLimits.standard.withLimit(name, value)),
      ));
    }
    out.writeln('  value    match  FP  FN  n/r  changes vs today');
    for (final (value, s) in rows) {
      final fixed = s.matched.difference(baseline.matched);
      final broken = baseline.matched.difference(s.matched);
      final changes = [
        for (final id in fixed) '+$id',
        for (final id in broken) '-$id',
      ];
      out.writeln(
        '  ${_n(value).padRight(8)} ${'${s.matches}'.padLeft(5)} '
        '${'${s.falsePositives.length}'.padLeft(3)} '
        '${'${s.falseNegatives.length}'.padLeft(3)} '
        '${'${s.undecided.length}'.padLeft(4)}  '
        '${value == current ? '(today) ' : ''}${changes.join(' ')}',
      );
    }
    final best = rows.map((r) => r.$2.matches).reduce(math.max);
    final runs = _runs([
      for (final (value, s) in rows)
        if (s.matches == best) value,
    ], step);
    final widest = runs.reduce((a, b) => (b.$2 - b.$1) > (a.$2 - a.$1) ? b : a);
    out
      ..writeln(
        '  best: $best/${fixtures.length} at '
        '${runs.map((r) => r.$1 == r.$2 ? _n(r.$1) : '${_n(r.$1)}..${_n(r.$2)}').join(', ')}',
      )
      ..writeln(
        '  middle of the widest best range: '
        '${_n(_round((widest.$1 + widest.$2) / 2))}',
      );
  }
  return out.toString();
}

class _Score {
  _Score(
    this.matched,
    this.falsePositives,
    this.falseNegatives,
    this.undecided,
  );
  final Set<String> matched;
  final List<String> falsePositives;
  final List<String> falseNegatives;

  /// With this value the photo can't decide and the scan would need the
  /// printed-text check, which wasn't stored: counted as not matching.
  final List<String> undecided;
  int get matches => matched.length;
}

_Score _score(List<ScanFixture> fixtures, ValidationLimits limits) {
  final matched = <String>{};
  final fp = <String>[];
  final fn = <String>[];
  final undecided = <String>[];
  for (final f in fixtures) {
    final ScanReplay r;
    try {
      r = replay(f, limits: limits);
    } on NotReplayable {
      undecided.add(f.id);
      continue;
    }
    if (r.matches) {
      matched.add(f.id);
    } else if (r.expected == null) {
      fp.add(f.id);
    } else if (r.pageIssue == null) {
      fn.add(f.id);
    }
  }
  return _Score(matched, fp, fn, undecided);
}

/// What each limit is compared with, measured on one fixture's own page; null
/// when the limit doesn't apply to it.
double? measured(String limit, PageReplay page, double aspect) {
  final m = page.measure;
  final q = page.quality;
  final r = m.region;
  final v = page.verdict;
  switch (limit) {
    case 'minDocumentCoverage':
      return page.coverage.method == null ? null : page.coverage.share;
    case 'minSharpness':
      return q.sharpness;
    case 'minBrightness':
      return q.brightness;
    case 'maxGlareShare':
      return q.glareShare;
    case 'edgeMargin':
      // Closest gap to an edge of whatever decided the framing.
      return v.gaps?.reduce(math.min);
    case 'minContact':
      // Longest stretch of an edge the area lies on, as a share of its side.
      if (r == null || v.method != FrameMethod.region) return null;
      final w = r.right - r.left;
      final h = r.bottom - r.top;
      if (w <= 0 || h <= 0) return null;
      return [
        r.contact[0] / h,
        r.contact[1] / w,
        r.contact[2] / h,
        r.contact[3] / w,
      ].reduce(math.max);
    case 'regionAspectTolerance' || 'uprightRegionTolerance':
      if (r == null || v.method != FrameMethod.region) return null;
      final w = r.right - r.left;
      final h = r.bottom - r.top;
      if (w <= 0 || h <= 0) return null;
      final fill = r.share * m.width * m.height / (w * h);
      final upright = fill >= DocumentFraming.uprightFill;
      if (upright != (limit == 'uprightRegionTolerance')) return null;
      return _shapeOff(w / h, aspect);
    case 'aspectTolerance':
      final o = m.outline;
      if (o == null || o.length != 4) return null;
      final xs = o.map((p) => p.x);
      final ys = o.map((p) => p.y);
      final w = xs.reduce(math.max) - xs.reduce(math.min);
      final h = ys.reduce(math.max) - ys.reduce(math.min);
      if (w <= 0 || h <= 0) return null;
      return _shapeOff(w / h, aspect);
  }
  return null;
}

/// How far (as a fraction) [ratio] is from the document's shape, either way
/// up.
double _shapeOff(double ratio, double aspect) => math.min(
  (ratio - aspect).abs() / aspect,
  (ratio - 1 / aspect).abs() * aspect,
);

void _measuredPerLabel(
  StringBuffer out,
  String limit,
  List<ScanFixture> fixtures,
) {
  final byLabel = <String, List<double>>{};
  for (final f in fixtures) {
    final value = measured(limit, replay(f).page, f.kind.aspectRatio);
    if (value != null) (byLabel[f.label] ??= []).add(value);
  }
  if (byLabel.isEmpty) {
    out.writeln('  measured: no fixture this limit applies to');
    return;
  }
  for (final e
      in byLabel.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    final v = e.value..sort();
    out.writeln(
      '  measured ${e.key.padRight(13)} n=${'${v.length}'.padLeft(2)}  '
      '${_n(v.first)}..${_n(v.last)}  [${v.map(_n).join(', ')}]',
    );
  }
}

List<(double, double)> _runs(List<double> values, double step) {
  final runs = <(double, double)>[];
  for (final v in values) {
    if (runs.isNotEmpty && (v - runs.last.$2) <= step * 1.5) {
      runs[runs.length - 1] = (runs.last.$1, v);
    } else {
      runs.add((v, v));
    }
  }
  return runs;
}

double _round(double v) => double.parse(v.toStringAsFixed(4));

String _n(double v) =>
    v.abs() >= 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(3);
