import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

@RoutePage()
class SettingsMain extends StatelessWidget {
  const SettingsMain({super.key});

  static const String routeName = '/settings';

  static AutoRoute get route => CustomRoute(
        page: SettingsRoute.page,
        path: routeName,
        fullscreenDialog: true,
      );

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class SettingsRoute {
  const SettingsRoute();

  static const Object page = Object();
}
