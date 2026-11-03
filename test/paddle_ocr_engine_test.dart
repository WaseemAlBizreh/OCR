import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_ocr_engine.dart';

/// Model loading only: a fake loader stands in for ONNX Runtime, and every
/// test stops before an image is opened.
void main() {
  final unavailable = throwsA(isA<ReaderUnavailableException>());

  test('a failed load is reported, and the next read loads again', () async {
    var loads = 0;
    final engine = PaddleOcrEngine(
      load: () async {
        loads++;
        throw StateError('no space left on device');
      },
    );

    await expectLater(engine.recognize('a.jpg'), unavailable);
    await expectLater(engine.recognize('a.jpg'), unavailable);
    expect(loads, 2);
  });

  test('a loader that throws at once is also retried', () async {
    var loads = 0;
    final engine = PaddleOcrEngine(
      load: () {
        loads++;
        throw StateError('no memory');
      },
    );

    await expectLater(engine.recognize('a.jpg'), unavailable);
    await expectLater(engine.recognize('a.jpg'), unavailable);
    expect(loads, 2);
  });

  test('reads that start together share one load', () async {
    var loads = 0;
    final pending = Completer<PaddleModels>();
    final engine = PaddleOcrEngine(
      load: () {
        loads++;
        return pending.future;
      },
    );

    final first = engine.recognize('a.jpg');
    final second = engine.recognize('b.jpg');
    pending.completeError(StateError('no memory'));

    await expectLater(first, unavailable);
    await expectLater(second, unavailable);
    expect(loads, 1);
  });

  test('the error says why the load failed', () async {
    final engine = PaddleOcrEngine(
      load: () async => throw StateError('no space left on device'),
    );

    await expectLater(
      engine.recognize('a.jpg'),
      throwsA(
        isA<ReaderUnavailableException>().having(
          (e) => '${e.cause}',
          'cause',
          contains('no space left on device'),
        ),
      ),
    );
  });
}
