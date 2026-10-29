import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/ocr/card_text_recognizer.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/ctc_decoder.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/db_postprocess.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/rtl_reorder.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// On-device Arabic + Latin card text with PaddleOCR PP-OCRv5 (ONNX Runtime):
/// DB detector finds the text lines, the Arabic CTC recognizer reads each one.
///
/// Models and their provenance: `assets/models/paddle/README.md`.
@lazySingleton
class PaddleOcrEngine implements CardTextRecognizer {
  static const _detAsset = 'assets/models/paddle/det.onnx';
  static const _recAsset = 'assets/models/paddle/arabic_rec.onnx';
  static const _dictAsset = 'assets/models/paddle/arabic_dict.txt';

  static const _detMaxSide = 960;
  static const _recHeight = 48;
  static const _recMaxWidth = 1600;
  static const _minConfidence = 0.3;

  static const _post = DbPostProcess();

  OrtSession? _det;
  OrtSession? _rec;
  CtcDecoder? _decoder;

  Future<void> _ensureLoaded() async {
    if (_det != null) return;
    final ort = OnnxRuntime();
    _det = await ort.createSessionFromAsset(_detAsset);
    _rec = await ort.createSessionFromAsset(_recAsset);
    final dict = (await rootBundle.loadString(_dictAsset))
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
    // The recognizer's last class is the space character.
    _decoder = CtcDecoder([...dict, ' ']);
  }

  @override
  Future<String> recognizeCardText(String imagePath) async =>
      (await recognize(imagePath)).text;

  /// Full result with per-line boxes and confidences, for the debug screen.
  ///
  /// [detMaxSide] is the longest side the detector sees; a full A4 page needs
  /// more than a card to keep small print readable.
  Future<PaddleResult> recognize(String imagePath, {int detMaxSide = _detMaxSide}) async {
    await _ensureLoaded();

    final image = cv.imread(imagePath);
    if (image.isEmpty) {
      image.dispose();
      throw StateError('Failed to read image: $imagePath');
    }

    try {
      final boxes = await _detect(image, detMaxSide);
      final lines = <PaddleLine>[];
      for (final box in boxes) {
        final line = await _recognize(image, box);
        if (line != null) lines.add(line);
      }
      return PaddleResult(_inReadingOrder(lines));
    } finally {
      image.dispose();
    }
  }

  // ---- detection ----------------------------------------------------------

  Future<List<TextBox>> _detect(cv.Mat image, int detMaxSide) async {
    final scale = math.min(1.0, detMaxSide / math.max(image.cols, image.rows));
    final w = math.max(32, (image.cols * scale / 32).round() * 32);
    final h = math.max(32, (image.rows * scale / 32).round() * 32);

    final resized = cv.resize(image, (w, h), interpolation: cv.INTER_LINEAR);
    final input = Float32List(3 * h * w);
    try {
      final px = resized.data; // BGR, interleaved
      const mean = [0.485, 0.456, 0.406];
      const std = [0.229, 0.224, 0.225];
      final plane = h * w;
      for (var i = 0; i < plane; i++) {
        for (var c = 0; c < 3; c++) {
          input[c * plane + i] = (px[i * 3 + c] / 255 - mean[c]) / std[c];
        }
      }
    } finally {
      resized.dispose();
    }

    final tensor = await OrtValue.fromList(input, [1, 3, h, w]);
    final outputs = await _det!.run({_det!.inputNames.first: tensor});
    final out = outputs.values.first;
    final probs = Float32List.fromList(
      [for (final v in await out.asFlattenedList()) (v as num).toDouble()],
    );
    await tensor.dispose();
    for (final value in outputs.values) {
      await value.dispose();
    }

    // Output is [1, 1, h, w]; use its own spatial size.
    final mapH = out.shape.length >= 2 ? out.shape[out.shape.length - 2] : h;
    final mapW = out.shape.last;
    return _post
        .boxes(probs, mapW, mapH)
        .map((b) => b.scaled(image.cols / mapW, image.rows / mapH))
        .toList();
  }

  // ---- recognition --------------------------------------------------------

  static final _digits = RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]');

  Future<PaddleLine?> _recognize(cv.Mat image, TextBox box) async {
    final x = box.left.floor().clamp(0, image.cols - 1);
    final y = box.top.floor().clamp(0, image.rows - 1);
    final w = (box.right.ceil() - x).clamp(1, image.cols - x);
    final h = (box.bottom.ceil() - y).clamp(1, image.rows - y);
    if (h < 4 || w < 4) return null;

    final region = image.region(cv.Rect(x, y, w, h));
    try {
      final first = await _readLine(region);

      // The card's guilloche background makes the recognizer drop digits (a
      // phone number lost 3 of 10 in testing). Contrast normalisation (CLAHE)
      // brings them back, so lines with digits get a second read and the one
      // with more digits wins.
      var best = first;
      if (first != null && _digits.hasMatch(first.text)) {
        final enhanced = _clahe(region);
        try {
          final second = await _readLine(enhanced);
          if (second != null && _digitCount(second.text) > _digitCount(first.text)) {
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
  cv.Mat _clahe(cv.Mat bgr) {
    final lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
    final channels = cv.split(lab);
    final clahe = cv.CLAHE(2.0, (4, 4));
    final lightness = clahe.apply(channels[0]);
    final merged = cv.merge(cv.VecMat.fromList([lightness, channels[1], channels[2]]));
    final result = cv.cvtColor(merged, cv.COLOR_Lab2BGR);
    for (final m in [lab, lightness, merged]) {
      m.dispose();
    }
    clahe.dispose();
    channels.dispose();
    return result;
  }

  /// Runs the recognizer on one line image; `null` for low-confidence reads.
  Future<({String text, double confidence})?> _readLine(cv.Mat line) async {
    final targetW =
        (_recHeight * line.cols / line.rows).round().clamp(16, _recMaxWidth).toInt();
    final resized =
        cv.resize(line, (targetW, _recHeight), interpolation: cv.INTER_CUBIC);

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
    final outputs = await _rec!.run({_rec!.inputNames.first: tensor});
    final out = outputs.values.first;
    final flat = await out.asFlattenedList();
    final shape = out.shape; // [1, T, classes]
    await tensor.dispose();
    for (final value in outputs.values) {
      await value.dispose();
    }

    final steps = shape[shape.length - 2];
    final classes = shape.last;
    final logits = [
      for (var t = 0; t < steps; t++)
        [
          for (var k = 0; k < classes; k++)
            (flat[t * classes + k] as num).toDouble(),
        ],
    ];
    final decoded = _decoder!.greedy(logits);
    if (decoded.confidence < _minConfidence) return null;

    final text = ParserUtils.normalizeArabic(RtlReorder.fix(decoded.text)).trim();
    if (text.isEmpty) return null;
    return (text: text, confidence: decoded.confidence);
  }

  // ---- ordering -----------------------------------------------------------

  /// Rows top to bottom; inside a row, right to left (the cards are Arabic).
  /// Each box is emitted as its own line, followed by the joined row when the
  /// row has several boxes, so label/value parsers can match either shape.
  List<PaddleLine> _inReadingOrder(List<PaddleLine> lines) {
    final sorted = [...lines]..sort((a, b) => a.box.centerY.compareTo(b.box.centerY));
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

  Future<void> dispose() async {
    await _det?.close();
    await _rec?.close();
    _det = null;
    _rec = null;
    _decoder = null;
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
