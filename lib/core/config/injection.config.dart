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

import '../../features/arabic_document_scan/data/arabic_ocr_engine.dart'
    as _i1054;
import '../../features/arabic_document_scan/data/document_scan_service.dart'
    as _i942;
import '../../features/arabic_document_scan/data/generic_arabic_extractor.dart'
    as _i516;
import '../../features/arabic_document_scan/data/opencv_image_enhancer.dart'
    as _i329;
import '../../features/arabic_document_scan/data/passport_mrz_extractor.dart'
    as _i540;

// initializes the registration of main-scope dependencies inside of GetIt
_i174.GetIt $initGetIt(
  _i174.GetIt getIt, {
  String? environment,
  _i526.EnvironmentFilter? environmentFilter,
}) {
  final gh = _i526.GetItHelper(getIt, environment, environmentFilter);
  gh.lazySingleton<_i1054.ArabicOcrEngine>(() => _i1054.ArabicOcrEngine());
  gh.lazySingleton<_i329.OpenCvImageEnhancer>(
    () => _i329.OpenCvImageEnhancer(),
  );
  gh.lazySingleton<_i516.GenericArabicExtractor>(
    () => _i516.GenericArabicExtractor(gh<_i1054.ArabicOcrEngine>()),
  );
  gh.lazySingleton<_i540.PassportMrzExtractor>(
    () => _i540.PassportMrzExtractor(gh<_i1054.ArabicOcrEngine>()),
  );
  gh.lazySingleton<_i942.DocumentScanService>(
    () => _i942.DocumentScanService(
      gh<_i540.PassportMrzExtractor>(),
      gh<_i516.GenericArabicExtractor>(),
      gh<_i329.OpenCvImageEnhancer>(),
      gh<_i1054.ArabicOcrEngine>(),
    ),
  );
  return getIt;
}
