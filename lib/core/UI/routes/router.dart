import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import
'router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(GlobalKey<NavigatorState> navigatorKey)
      : super(navigatorKey: navigatorKey);

  @override
  RouteType get defaultRouteType => RouteType.adaptive();

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: AppHomeRoute.page, initial: true),
        AutoRoute(page: MrzScanRoute.page),
        AutoRoute(page: DocumentScanHomeRoute.page),
        AutoRoute(page: DocumentCaptureRoute.page),
      ];
}
