// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i5;
import 'package:flutter/material.dart' as _i6;
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart'
    as _i7;
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart'
    as _i8;
import 'package:mrz/features/arabic_document_scan/presentation/pages/document_capture_page.dart'
    as _i2;
import 'package:mrz/features/arabic_document_scan/presentation/pages/document_scan_home_page.dart'
    as _i3;
import 'package:mrz/features/home/presentation/pages/app_home_page.dart' as _i1;
import 'package:mrz/features/mrz_scan/presentation/pages/mrz_scan_page.dart'
    as _i4;

/// generated route for
/// [_i1.AppHomePage]
class AppHomeRoute extends _i5.PageRouteInfo<void> {
  const AppHomeRoute({List<_i5.PageRouteInfo>? children})
    : super(AppHomeRoute.name, initialChildren: children);

  static const String name = 'AppHomeRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return const _i1.AppHomePage();
    },
  );
}

/// generated route for
/// [_i2.DocumentCapturePage]
class DocumentCaptureRoute extends _i5.PageRouteInfo<DocumentCaptureRouteArgs> {
  DocumentCaptureRoute({
    _i6.Key? key,
    required _i7.DocumentType documentType,
    String? countryCode,
    _i8.IdCardSide idCardSide = _i8.IdCardSide.front,
    List<_i5.PageRouteInfo>? children,
  }) : super(
         DocumentCaptureRoute.name,
         args: DocumentCaptureRouteArgs(
           key: key,
           documentType: documentType,
           countryCode: countryCode,
           idCardSide: idCardSide,
         ),
         initialChildren: children,
       );

  static const String name = 'DocumentCaptureRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DocumentCaptureRouteArgs>();
      return _i2.DocumentCapturePage(
        key: args.key,
        documentType: args.documentType,
        countryCode: args.countryCode,
        idCardSide: args.idCardSide,
      );
    },
  );
}

class DocumentCaptureRouteArgs {
  const DocumentCaptureRouteArgs({
    this.key,
    required this.documentType,
    this.countryCode,
    this.idCardSide = _i8.IdCardSide.front,
  });

  final _i6.Key? key;

  final _i7.DocumentType documentType;

  final String? countryCode;

  final _i8.IdCardSide idCardSide;

  @override
  String toString() {
    return 'DocumentCaptureRouteArgs{key: $key, documentType: $documentType, countryCode: $countryCode, idCardSide: $idCardSide}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DocumentCaptureRouteArgs) return false;
    return key == other.key &&
        documentType == other.documentType &&
        countryCode == other.countryCode &&
        idCardSide == other.idCardSide;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      documentType.hashCode ^
      countryCode.hashCode ^
      idCardSide.hashCode;
}

/// generated route for
/// [_i3.DocumentScanHomePage]
class DocumentScanHomeRoute extends _i5.PageRouteInfo<void> {
  const DocumentScanHomeRoute({List<_i5.PageRouteInfo>? children})
    : super(DocumentScanHomeRoute.name, initialChildren: children);

  static const String name = 'DocumentScanHomeRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return const _i3.DocumentScanHomePage();
    },
  );
}

/// generated route for
/// [_i4.MrzScanPage]
class MrzScanRoute extends _i5.PageRouteInfo<void> {
  const MrzScanRoute({List<_i5.PageRouteInfo>? children})
    : super(MrzScanRoute.name, initialChildren: children);

  static const String name = 'MrzScanRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return const _i4.MrzScanPage();
    },
  );
}
