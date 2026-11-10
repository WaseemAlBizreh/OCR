// Replays every labelled real scan in test/fixtures/scans/ through the
// decision code in this checkout and compares the verdict with the label.
//
// Strict by default: a fixture whose replayed verdict differs from its label
// fails its test, so a change to a rule or limit that breaks a known scan
// fails `flutter test`. Not failed: labels marked "unsure", fixtures that
// can't be replayed, and the [knownExceptions] below. A known exception that
// starts to match fails too, so it is taken off the list. The table is always
// printed. IDLENS_REGRESSION_STRICT=0 only reports (for exploring a change).
//
//   flutter test test/regression/scan_replay_test.dart
//   IDLENS_REGRESSION_STRICT=0 flutter test test/regression/scan_replay_test.dart
//
// IDLENS_REPLAY_TAG (optional) is printed in the table header, to tell runs
// against different checkouts apart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scan_replay.dart';

const fixturesRoot = 'test/fixtures/scans';

/// Scans that no limit or rule in the decision code can get right, with why.
/// Adding one is a deliberate choice: say what would fix it.
const knownExceptions = {
  // Not listed: certificate/cut/2026-11-09_off-left-edge (measured before
  // 0.4.0, contact 0, so no edge rule sees its cut). It matches only because
  // its coverage, 0.59, is under the 0.60 distance limit: right issue, wrong
  // reason. If a distance change breaks it, list it here, don't tune for it.
  // Dark (80.5) and blurry (25.9), but the bright area runs along the top
  // (contact 351 of 354) and is judged cut first, which wins over clarity.
  // Its top may really be cut; the label needs the user's check of the photo.
  'passport/dark/2026-11-10_dark-blurry': 'judged cut; label to recheck',
};

void main() {
  // The scans hold personal data and are kept out of git and pub.dev, so a
  // checkout without them skips this test instead of failing.
  if (!Directory(fixturesRoot).existsSync()) {
    test('$fixturesRoot is not present; skipped', () {}, skip: true);
    return;
  }
  final strict = Platform.environment['IDLENS_REGRESSION_STRICT'] != '0';
  final tag = Platform.environment['IDLENS_REPLAY_TAG'];
  final fixtures = ScanFixture.loadAll(fixturesRoot);
  final rows = <_Row>[];

  test('the fixture set is not empty and every result parses', () {
    expect(fixtures, isNotEmpty);
  });

  for (final fixture in fixtures) {
    test(fixture.id, () {
      ScanReplay? result;
      NotReplayable? missing;
      try {
        result = replay(fixture);
      } on NotReplayable catch (e) {
        missing = e;
      }
      rows.add(_Row(fixture, result, missing));
      final exception = knownExceptions[fixture.id];
      if (strict && result != null && !fixture.unsure && exception != null) {
        expect(
          result.matches,
          isFalse,
          reason:
              '${fixture.id} now matches its label: take it off '
              'knownExceptions ($exception)',
        );
      } else if (strict && result != null && !fixture.unsure) {
        expect(
          result.matches,
          isTrue,
          reason:
              '${fixture.id}: labelled ${fixture.label}, expected '
              '${result.expected?.name ?? 'no issue'}, replayed '
              '${result.pageIssue?.name ?? 'no issue'} '
              '(${result.decidedBy}; scan ${result.status.name})',
        );
      }
    });
  }

  test('every known exception is a fixture', () {
    final ids = {for (final f in fixtures) f.id};
    expect(knownExceptions.keys.where((id) => !ids.contains(id)), isEmpty);
  });

  tearDownAll(() => stdout.write(_report(rows, strict: strict, tag: tag)));
}

class _Row {
  _Row(this.fixture, this.result, this.missing);
  final ScanFixture fixture;
  final ScanReplay? result;
  final NotReplayable? missing;
}

String _report(List<_Row> rows, {required bool strict, String? tag}) {
  final header = [
    'kind',
    'label',
    'name',
    'expected',
    'replayed',
    'ok',
    'method',
    'decided by',
    'scan',
    'device said',
    'gaps L,T,R,B',
    'contact',
    'ratio',
    'fill',
    'coverage',
    'sharp',
  ];
  final table = <List<String>>[];
  for (final row in rows) {
    final f = row.fixture;
    final label = f.unsure ? '${f.label}?' : f.label;
    final r = row.result;
    final device = [
      '${f.result['status']}',
      if (f.result['issue'] != null) '${f.result['issue']}',
    ].join('/');
    if (r == null) {
      table.add([
        f.folder,
        label,
        f.name,
        labels[f.label]?.name ?? 'none',
        '${row.missing}',
        '-',
        ...List.filled(header.length - 6, ''),
      ]);
      continue;
    }
    final n = keyNumbers(r.page);
    final sides = r.issueSides.map((s) => s.name).join('+');
    table.add([
      f.folder,
      label,
      f.name,
      r.expected?.name ?? 'none',
      r.pageIssue?.name ?? 'none',
      r.matches ? 'yes' : (knownExceptions.containsKey(f.id) ? 'known' : 'NO'),
      r.page.verdict.method.name,
      r.decidedBy,
      '${r.status.name}${sides.isEmpty ? '' : ' [$sides]'}',
      device,
      n['gaps L,T,R,B']!,
      n['contact']!,
      n['ratio']!,
      n['fill']!,
      n['coverage']!,
      n['sharp']!,
    ]);
  }

  final widths = [
    for (var c = 0; c < header.length; c++)
      [
        header[c],
        for (final row in table) row[c],
      ].map((s) => s.length).reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> cells) => [
    for (var c = 0; c < cells.length; c++) cells[c].padRight(widths[c]),
  ].join(' | ').trimRight();

  final replayed = [
    for (final row in rows)
      if (row.result != null) row.result!,
  ];
  final falseCuts = replayed.where((r) => r.falseCutOff).toList();
  final missedCuts = replayed.where((r) => r.missedCut).toList();
  final other = replayed
      .where((r) => !r.matches && !r.falseCutOff && !r.missedCut)
      .toList();
  final notReplayable = rows.where((r) => r.result == null).toList();
  String names(List<ScanReplay> list) => list.isEmpty
      ? ''
      : ': ${list.map((r) => r.fixture.id + (r.fixture.unsure ? ' (label unsure)' : '')).join(', ')}';

  final out = StringBuffer()
    ..writeln()
    ..writeln(
      'idlens scan replay${tag == null ? '' : ' [$tag]'}'
      '${strict ? ' (strict)' : ''}: ${rows.length} fixtures',
    )
    ..writeln(line(header))
    ..writeln(line([for (final w in widths) '-' * w]));
  for (final row in table) {
    out.writeln(line(row));
  }
  out
    ..writeln()
    ..writeln(
      'matched ${replayed.where((r) => r.matches).length} of '
      '${replayed.length} replayed',
    )
    ..writeln(
      'false cut-offs (good judged cut): ${falseCuts.length}${names(falseCuts)}',
    )
    ..writeln(
      'missed cuts (cut or far not judged documentNotInFrame): ${missedCuts.length}${names(missedCuts)}',
    )
    ..writeln('other mismatches: ${other.length}${names(other)}')
    ..writeln('not replayable: ${notReplayable.length}')
    ..writeln('("?" after a label: label_confidence is unsure)')
    ..writeln(
      'known exceptions (not failed): '
      '${knownExceptions.entries.map((e) => '${e.key} (${e.value})').join(', ')}',
    );
  for (final row in notReplayable) {
    out.writeln('  ${row.fixture.id}: ${row.missing}');
  }
  return out.toString();
}
