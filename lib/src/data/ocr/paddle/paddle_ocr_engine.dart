import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:idlens/src/data/front/parser_utils.dart';
import 'package:idlens/src/data/ocr/card_text_recognizer.dart';
import 'package:idlens/src/data/ocr/paddle/ctc_decoder.dart';
import 'package:idlens/src/data/ocr/paddle/db_postprocess.dart';
import 'package:idlens/src/data/ocr/paddle/rtl_reorder.dart';
import 'package:idlens/src/domain/scan_deadline.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// The detector, the recognizer and its decoder, loaded together.
typedef PaddleModels = ({OrtSession det, OrtSession rec, CtcDecoder decoder});

/// The text reader's models could not be loaded, for example because the
/// phone had no storage left to unpack them. Apps see it as
/// `ScanIssue.readerUnavailable`; the next read tries to load again.
class ReaderUnavailableException implements Exception {
  const ReaderUnavailableException(this.cause);

  /// The error that stopped the load.
  final Object cause;

  @override
  String toString() => 'ReaderUnavailableException: $cause';
}

/// On-device Arabic + Latin card text with PaddleOCR PP-OCRv5 (ONNX Runtime):
/// DB detector finds the text lines, the Arabic CTC recognizer reads each one.
///
/// Models and their provenance: `assets/models/paddle/README.md`.
class PaddleOcrEngine implements CardTextRecognizer {
  /// [load] replaces the model loading, for tests.
  PaddleOcrEngine({Future<PaddleModels> Function()? load})
    : _load = load ?? _loadModels;

  static const _detAsset =
      'packages/idlens/assets/models/paddle/idlens_det_v1.onnx';
  static const _recAsset =
      'packages/idlens/assets/models/paddle/idlens_arabic_rec_v1.onnx';
  static const _dictAsset =
      'packages/idlens/assets/models/paddle/idlens_arabic_dict_v1.txt';

  static const _detMaxSide = 960;
  static const _recHeight = 48;
  static const _recMaxWidth = 1600;
  static const _minConfidence = 0.3;

  static const _post = DbPostProcess();

  final Future<PaddleModels> Function() _load;
  Future<PaddleModels>? _loading;

  /// The models, loaded once and shared by every read, including reads that
  /// start together. A failed load is forgotten, so the next read tries again
  /// instead of every read failing until the app restarts.
  Future<PaddleModels> _models() async {
    Future<PaddleModels>? loading;
    try {
      loading = _loading ??= _load();
      return await loading;
    } catch (error) {
      // A read that started later may already be loading again.
      if (identical(_loading, loading)) _loading = null;
      throw ReaderUnavailableException(error);
    }
  }

  /// Loads all three parts, or none: anything loaded before a failure is
  /// closed again.
  static Future<PaddleModels> _loadModels() async {
    final ort = OnnxRuntime();
    OrtSession? det;
    OrtSession? rec;
    try {
      det = await ort.createSessionFromAsset(_detAsset);
      rec = await ort.createSessionFromAsset(_recAsset);
      final dict = (await rootBundle.loadString(
        _dictAsset,
      )).split('\n').where((line) => line.isNotEmpty).toList();
      // The recognizer's last class is the space character.
      return (det: det, rec: rec, decoder: CtcDecoder([...dict, ' ']));
    } catch (_) {
      for (final session in [det, rec]) {
        try {
          await session?.close();
        } catch (_) {
          // The load error is the one worth reporting.
        }
      }
      rethrow;
    }
  }

  @override
  Future<String> recognizeCardText(String imagePath) async =>
      (await recognize(imagePath)).text;

  /// Full result with per-line boxes and confidences, for the debug screen.
  ///
  /// [detMaxSide] is the longest side the detector sees; a full A4 page needs
  /// more than a card to keep small print readable.
  ///
  /// Throws [ReaderUnavailableException] when the models can't be loaded, and
  /// [ScanTimedOutException] between lines once the read's time limit passed.
  Future<PaddleResult> recognize(
    String imagePath, {
    int detMaxSide = _detMaxSide,
  }) async {
    ScanDeadline.check();
    final models = await _models();

    final image = await cv.imreadAsync(imagePath);
    if (image.isEmpty) {
      image.dispose();
      throw StateError('Failed to read image: $imagePath');
    }

    try {
      final boxes = await _detect(models.det, image, detMaxSide);
      final lines = <PaddleLine>[];
      for (final box in boxes) {
        ScanDeadline.check();
        final line = await _recognize(models, image, box);
        if (line != null) lines.add(line);
      }
      return PaddleResult(_inReadingOrder(lines));
    } finally {
      image.dispose();
    }
  }

  // ---- detection ----------------------------------------------------------

  Future<List<TextBox>> _detect(
    OrtSession det,
    cv.Mat image,
    int detMaxSide,
  ) async {
    final scale = math.min(1.0, detMaxSide / math.max(image.cols, image.rows));
    final w = math.max(32, (image.cols * scale / 32).round() * 32);
    final h = math.max(32, (image.rows * scale / 32).round() * 32);

    final resized = await cv.resizeAsync(image, (
      w,
      h,
    ), interpolation: cv.INTER_LINEAR);
    final Uint8List pixels;
    try {
      // A copy, so the worker isolate can take it after the Mat is freed.
      pixels = Uint8List.fromList(resized.data); // BGR, interleaved
    } finally {
      resized.dispose();
    }
    final input = await _inBackground(_detectorInput, pixels, w * h);

    final tensor = await OrtValue.fromList(input, [1, 3, h, w]);
    final outputs = await det.run({det.inputNames.first: tensor});
    final out = outputs.values.first;
    final probs = _floats(await out.asFlattenedList());
    await tensor.dispose();
    for (final value in outputs.values) {
      await value.dispose();
    }

    // Output is [1, 1, h, w]; use its own spatial size.
    final mapH = out.shape.length >= 2 ? out.shape[out.shape.length - 2] : h;
    final mapW = out.shape.last;
    final boxes = await _inBackground(_boxes, probs, (mapW, mapH));
    return boxes
        .map((b) => b.scaled(image.cols / mapW, image.rows / mapH))
        .toList();
  }

  /// Runs [work] on a short-lived worker isolate. The detector's input and its
  /// output map each take about a million steps, which would stop the app's
  /// frames if run on the isolate that called the scan.
  ///
  /// Static, so the closure sent to the worker holds only [a] and [b], never
  /// a native `Mat` from the caller's scope.
  static Future<R> _inBackground<R, A, B>(R Function(A, B) work, A a, B b) =>
      Isolate.run(() => work(a, b));

  static List<TextBox> _boxes(Float32List map, (int, int) size) =>
      _post.boxes(map, size.$1, size.$2);

  /// BGR pixels to the detector's normalised, channel-first input.
  static Float32List _detectorInput(Uint8List px, int plane) {
    const mean = [0.485, 0.456, 0.406];
    const std = [0.229, 0.224, 0.225];
    final input = Float32List(3 * plane);
    for (var i = 0; i < plane; i++) {
      for (var c = 0; c < 3; c++) {
        input[c * plane + i] = (px[i * 3 + c] / 255 - mean[c]) / std[c];
      }
    }
    return input;
  }

  /// A model output as floats. The plugin already returns a `Float32List` for
  /// float tensors on Android and iOS, so this normally copies nothing.
  static Float32List _floats(List<dynamic> values) => values is Float32List
      ? values
      : Float32List.fromList([for (final v in values) (v as num).toDouble()]);

  // ---- recognition --------------------------------------------------------

  static final _digits = RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]');

  Future<PaddleLine?> _recognize(
    PaddleModels models,
    cv.Mat image,
    TextBox box,
  ) async {
    final x = box.left.floor().clamp(0, image.cols - 1);
    final y = box.top.floor().clamp(0, image.rows - 1);
    final w = (box.right.ceil() - x).clamp(1, image.cols - x);
    final h = (box.bottom.ceil() - y).clamp(1, image.rows - y);
    if (h < 4 || w < 4) return null;

    final region = image.region(cv.Rect(x, y, w, h));
    try {
      final first = await _readLine(models, region);

      // The card's guilloche background makes the recognizer drop digits (a
      // phone number lost 3 of 10 in testing). Contrast normalisation (CLAHE)
      // brings them back, so lines with digits get a second read and the one
      // with more digits wins.
      var best = first;
      if (first != null && _digits.hasMatch(first.text)) {
        final enhanced = await _clahe(region);
        try {
          final second = await _readLine(models, enhanced);
          if (second != null &&
              _digitCount(second.text) > _digitCount(first.text)) {
            best = second;
          }
        } finally {
          enhanced.dispose();
        }
      }
      return best == null ? null : PaddleLine(best.text, best.confidence, box);
    } finally {
      region.dispose();
    }
  }

  int _digitCount(String text) => _digits.allMatches(text).length;

  /// Contrast-limited adaptive histogram equalisation on the lightness channel.
  Future<cv.Mat> _clahe(cv.Mat bgr) async {
    final lab = await cv.cvtColorAsync(bgr, cv.COLOR_BGR2Lab);
    final channels = await cv.splitAsync(lab);
    final clahe = cv.CLAHE(2.0, (4, 4));
    final lightness = await clahe.applyAsync(channels[0]);
    final merged = await cv.mergeAsync(
      cv.VecMat.fromList([lightness, channels[1], channels[2]]),
    );
    final result = await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
    for (final m in [lab, lightness, merged]) {
      m.dispose();
    }
    clahe.dispose();
    channels.dispose();
    return result;
  }

  /// Runs the recognizer on one line image; `null` for low-confidence reads.
  Future<({String text, double confidence})?> _readLine(
    PaddleModels models,
    cv.Mat line,
  ) async {
    final targetW = (_recHeight * line.cols / line.rows)
        .round()
        .clamp(16, _recMaxWidth)
        .toInt();
    final resized = await cv.resizeAsync(line, (
      targetW,
      _recHeight,
    ), interpolation: cv.INTER_CUBIC);

    final input = Float32List(3 * _recHeight * targetW);
    try {
      final px = resized.data;
      final plane = _recHeight * targetW;
      for (var i = 0; i < plane; i++) {
        for (var c = 0; c < 3; c++) {
          input[c * plane + i] = (px[i * 3 + c] / 255 - 0.5) / 0.5;
        }
      }
    } finally {
      resized.dispose();
    }

    final tensor = await OrtValue.fromList(input, [1, 3, _recHeight, targetW]);
    final outputs = await models.rec.run({models.rec.inputNames.first: tensor});
    final out = outputs.values.first;
    final flat = _floats(await out.asFlattenedList());
    final shape = out.shape; // [1, T, classes]
    await tensor.dispose();
    for (final value in outputs.values) {
      await value.dispose();
    }

    final decoded = models.decoder.greedy(flat, classes: shape.last);
    if (decoded.confidence < _minConfidence) return null;

    final text = ParserUtils.normalizeArabic(
      RtlReorder.fix(decoded.text),
    ).trim();
    if (text.isEmpty) return null;
    return (text: text, confidence: decoded.confidence);
  }

  // ---- ordering -----------------------------------------------------------

  /// Rows top to bottom; inside a row, right to left (the cards are Arabic).
  /// Each box is emitted as its own line, followed by the joined row when the
  /// row has several boxes, so label/value parsers can match either shape.
  List<PaddleLine> _inReadingOrder(List<PaddleLine> lines) {
    final sorted = [...lines]
      ..sort((a, b) => a.box.centerY.compareTo(b.box.centerY));
    final rows = <List<PaddleLine>>[];
    for (final line in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null &&
          (line.box.centerY - row.first.box.centerY).abs() <
              row.first.box.height * 0.6) {
        row.add(line);
      } else {
        rows.add([line]);
      }
    }

    final ordered = <PaddleLine>[];
    for (final row in rows) {
      row.sort((a, b) => b.box.right.compareTo(a.box.right));
      ordered.addAll(row);
      if (row.length > 1) {
        final joined = row.map((l) => l.text).join(' ');
        final confidence =
            row.map((l) => l.confidence).reduce((a, b) => a + b) / row.length;
        ordered.add(PaddleLine(joined, confidence, row.first.box));
      }
    }
    return ordered;
  }
}

class PaddleLine {
  const PaddleLine(this.text, this.confidence, this.box);

  final String text;
  final double confidence;
  final TextBox box;
}

class PaddleResult {
  const PaddleResult(this.lines);

  final List<PaddleLine> lines;

  String get text => lines.map((l) => l.text).join('\n');
}
