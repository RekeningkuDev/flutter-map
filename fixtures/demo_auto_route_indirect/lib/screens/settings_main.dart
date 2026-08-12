import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// Getter form at the top level.
@RoutePage()
class SettingsMain extends StatelessWidget {
  const SettingsMain({super.key});

  static const routeName = '/settings';

  static AutoRoute get route => AdaptiveRoute(
        page: SettingsRoute.page,
        path: routeName,
        fullscreenDialog: true,
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
