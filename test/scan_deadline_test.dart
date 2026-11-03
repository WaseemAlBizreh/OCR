import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/scan_deadline.dart';

void main() {
  const limit = Duration(milliseconds: 50);

  test('without a limit the read runs to the end', () async {
    final value = await ScanDeadline.run(null, () async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ScanDeadline.check();
      return 'read';
    }, () => 'timed out');
    expect(value, 'read');
  });

  test('a read that ends in time keeps its value', () async {
    final value = await ScanDeadline.run(limit, () async {
      ScanDeadline.check();
      return 'read';
    }, () => 'timed out');
    expect(value, 'read');
  });

  test('a stuck read returns on time with the timeout value', () async {
    final stuck = Completer<String>();
    final clock = Stopwatch()..start();
    final value = await ScanDeadline.run(
      limit,
      () => stuck.future,
      () => 'timed out',
    );
    expect(value, 'timed out');
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('a read past its limit stops at the next check', () async {
    final steps = <int>[];
    final stopped = Completer<Object>();
    final value = await ScanDeadline.run(limit, () async {
      try {
        for (var step = 0; step < 20; step++) {
          ScanDeadline.check();
          steps.add(step);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return 'read';
      } catch (error) {
        stopped.complete(error);
        return 'stopped';
      }
    }, () => 'timed out');
    expect(value, 'timed out');
    expect(await stopped.future, isA<ScanTimedOutException>());
    // The steps after the limit were skipped, in the background too.
    expect(steps.length, lessThan(6));
  });

  test('a check outside a read with a limit does nothing', () {
    expect(ScanDeadline.check, returnsNormally);
  });
}
