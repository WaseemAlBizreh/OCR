// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i4;
import 'package:flutter/material.dart' as _i5;
import 'package:mrz/features/home/presentation/pages/app_home_page.dart' as _i1;
import 'package:mrz/features/identity_scan/domain/document_kind.dart' as _i6;
import 'package:mrz/features/identity_scan/presentation/pages/identity_flow_page.dart'
    as _i2;
import 'package:mrz/features/mrz_scan/presentation/pages/mrz_scan_page.dart'
    as _i3;

/// generated route for
/// [_i1.AppHomePage]
class AppHomeRoute extends _i4.PageRouteInfo<void> {
  const AppHomeRoute({List<_i4.PageRouteInfo>? children})
    : super(AppHomeRoute.name, initialChildren: children);

  static const String name = 'AppHomeRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i1.AppHomePage();
    },
  );
}

/// generated route for
/// [_i2.IdentityFlowPage]
class IdentityFlowRoute extends _i4.PageRouteInfo<IdentityFlowRouteArgs> {
  IdentityFlowRoute({
    _i5.Key? key,
    required _i6.DocumentKind kind,
    List<_i4.PageRouteInfo>? children,
  }) : super(
         IdentityFlowRoute.name,
         args: IdentityFlowRouteArgs(key: key, kind: kind),
         initialChildren: children,
       );

  static const String name = 'IdentityFlowRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IdentityFlowRouteArgs>();
      return _i2.IdentityFlowPage(key: args.key, kind: args.kind);
    },
  );
}

class IdentityFlowRouteArgs {
  const IdentityFlowRouteArgs({this.key, required this.kind});

  final _i5.Key? key;

  final _i6.DocumentKind kind;

  @override
  String toString() {
    return 'IdentityFlowRouteArgs{key: $key, kind: $kind}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IdentityFlowRouteArgs) return false;
    return key == other.key && kind == other.kind;
  }

  @override
  int get hashCode => key.hashCode ^ kind.hashCode;
}

/// generated route for
/// [_i3.MrzScanPage]
class MrzScanRoute extends _i4.PageRouteInfo<void> {
  const MrzScanRoute({List<_i4.PageRouteInfo>? children})
    : super(MrzScanRoute.name, initialChildren: children);

  static const String name = 'MrzScanRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i3.MrzScanPage();
    },
  );
}
