// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../../features/identity_scan/data/identity_scan_service.dart' as _i201;
import '../../features/identity_scan/data/image/image_ops.dart' as _i507;
import '../../features/identity_scan/data/mrz/mrz_reader.dart' as _i537;
import '../../features/identity_scan/data/ocr/ocr_engine.dart' as _i77;
import '../../features/identity_scan/data/ocr/paddle/paddle_ocr_engine.dart'
    as _i800;
import '../../features/identity_scan/data/ocr/paddle/passport/mlkit_latin_reader.dart'
    as _i487;
import '../../features/identity_scan/data/ocr/paddle/passport/paddle_passport_mrz_reader.dart'
    as _i235;
import '../../features/identity_scan/data/ocr/paddle/passport/paddle_passport_scan_service.dart'
    as _i1039;
import '../../features/identity_scan/data/ocr/paddle/passport/paddle_passport_text_reader.dart'
    as _i453;

// initializes the registration of main-scope dependencies inside of GetIt
_i174.GetIt $initGetIt(
  _i174.GetIt getIt, {
  String? environment,
  _i526.EnvironmentFilter? environmentFilter,
}) {
  final gh = _i526.GetItHelper(getIt, environment, environmentFilter);
  gh.lazySingleton<_i507.ImageOps>(() => _i507.ImageOps());
  gh.lazySingleton<_i77.OcrEngine>(() => _i77.OcrEngine());
  gh.lazySingleton<_i800.PaddleOcrEngine>(() => _i800.PaddleOcrEngine());
  gh.lazySingleton<_i487.MlKitLatinReader>(() => _i487.MlKitLatinReader());
  gh.lazySingleton<_i453.PaddlePassportTextReader>(
    () => _i453.PaddlePassportTextReader(
      gh<_i800.PaddleOcrEngine>(),
      gh<_i487.MlKitLatinReader>(),
    ),
  );
  gh.lazySingleton<_i235.PaddlePassportMrzReader>(
    () => _i235.PaddlePassportMrzReader(
      gh<_i487.MlKitLatinReader>(),
      gh<_i800.PaddleOcrEngine>(),
      gh<_i507.ImageOps>(),
    ),
  );
  gh.lazySingleton<_i537.MrzReader>(
    () => _i537.MrzReader(gh<_i77.OcrEngine>(), gh<_i507.ImageOps>()),
  );
  gh.lazySingleton<_i201.IdentityScanService>(
    () => _i201.IdentityScanService(
      gh<_i507.ImageOps>(),
      gh<_i77.OcrEngine>(),
      gh<_i537.MrzReader>(),
    ),
  );
  gh.lazySingleton<_i1039.PaddlePassportScanService>(
    () => _i1039.PaddlePassportScanService(
      gh<_i487.MlKitLatinReader>(),
      gh<_i235.PaddlePassportMrzReader>(),
      gh<_i453.PaddlePassportTextReader>(),
    ),
  );
  return getIt;
}
