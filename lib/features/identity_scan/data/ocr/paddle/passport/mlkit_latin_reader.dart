import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

/// What ML Kit read from one image: the whole text and its lines with boxes.
class MlKitPage {
  const MlKitPage(this.text, this.lines);

  final String text;
  final List<PassportLine> lines;
}

/// ML Kit (Latin) for the Paddle passport pipeline.
///
/// Separate from the classic `OcrEngine` on purpose: that class also carries
/// Tesseract, and the Paddle pipeline must not depend on it.
@lazySingleton
class MlKitLatinReader {
  TextRecognizer? _latin;

  Future<MlKitPage?> read(String imagePath) async {
    try {
      _latin ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result =
          await _latin!.processImage(InputImage.fromFilePath(imagePath));
      if (result.text.trim().isEmpty) return null;
      return MlKitPage(result.text.trim(), [
        for (final block in result.blocks)
          for (final line in block.lines)
            PassportLine(
              line.text,
              line.boundingBox.left,
              line.boundingBox.top,
              line.boundingBox.right,
              line.boundingBox.bottom,
            ),
      ]);
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _latin?.close();
    _latin = null;
  }
}
