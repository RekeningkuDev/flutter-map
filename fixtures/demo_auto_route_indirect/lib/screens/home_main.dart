import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

/// Relative child path: resolves against the shell's path.
@RoutePage()
class HomeMain extends StatelessWidget {
  const HomeMain({super.key});

  static const String routeName = 'home';

  static AutoRoute get route => AdaptiveRoute(
        page: HomeRoute.page,
        path: routeName,
      );

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class HomeRoute {
  const HomeRoute();

  static const Object page = Object();
}
