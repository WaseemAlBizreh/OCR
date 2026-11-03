import 'package:idlens/src/data/identity_scan_service.dart';
import 'package:idlens/src/data/image/document_frame_checker.dart';
import 'package:idlens/src/data/image/frame_edge_checker.dart';
import 'package:idlens/src/data/image/image_ops.dart';
import 'package:idlens/src/data/image/image_quality_checker.dart';
import 'package:idlens/src/data/mrz/mrz_reader.dart';
import 'package:idlens/src/data/ocr/ocr_engine.dart';
import 'package:idlens/src/data/ocr/paddle/civil_registry/civil_registry_scan_service.dart';
import 'package:idlens/src/data/ocr/paddle/civil_registry/civil_registry_text_reader.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_ocr_engine.dart';
import 'package:idlens/src/data/ocr/paddle/passport/mlkit_latin_reader.dart';
import 'package:idlens/src/data/ocr/paddle/passport/paddle_passport_mrz_reader.dart';
import 'package:idlens/src/data/ocr/paddle/passport/paddle_passport_scan_service.dart';
import 'package:idlens/src/data/ocr/paddle/passport/paddle_passport_text_reader.dart';

/// The package's internal object graph.
///
/// Every service is created on first use and then shared, so the ONNX models
/// and the ML Kit recognizers load once per app run. It is deliberately a plain
/// class and not a service locator: a host app keeps its own dependency
/// injection without clashing with ours.
class IdLensServices {
  IdLensServices._();

  static final IdLensServices instance = IdLensServices._();

  late final ImageOps imageOps = ImageOps();
  late final OcrEngine ocrEngine = OcrEngine();
  late final PaddleOcrEngine paddleOcrEngine = PaddleOcrEngine();
  late final MlKitLatinReader mlKitLatinReader = MlKitLatinReader();

  late final CivilRegistryTextReader civilRegistryTextReader =
      CivilRegistryTextReader(paddleOcrEngine, mlKitLatinReader);
  late final PaddlePassportTextReader passportTextReader =
      PaddlePassportTextReader(paddleOcrEngine, mlKitLatinReader);
  late final ImageQualityChecker imageQualityChecker = ImageQualityChecker(
    imageOps,
  );
  late final DocumentFrameChecker documentFrameChecker = DocumentFrameChecker();
  late final FrameEdgeChecker frameEdgeChecker = FrameEdgeChecker(
    mlKitLatinReader,
  );
  late final PaddlePassportMrzReader passportMrzReader =
      PaddlePassportMrzReader(mlKitLatinReader, paddleOcrEngine, imageOps);
  late final MrzReader mrzReader = MrzReader(ocrEngine, imageOps);

  late final CivilRegistryScanService civilRegistryScanService =
      CivilRegistryScanService(civilRegistryTextReader, imageOps);
  late final PaddlePassportScanService passportScanService =
      PaddlePassportScanService(
        mlKitLatinReader,
        passportMrzReader,
        passportTextReader,
      );
  late final IdentityScanService identityScanService = IdentityScanService(
    imageOps,
    mrzReader,
  );
}
