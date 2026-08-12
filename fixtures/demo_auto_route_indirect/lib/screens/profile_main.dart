import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

/// Absolute child path: escapes the shell's path prefix.
@RoutePage()
class ProfileMain extends StatelessWidget {
  const ProfileMain({super.key});

  static const String routeName = '/profile';

  static final AutoRoute route = AdaptiveRoute(
    page: ProfileRoute.page,
    path: routeName,
  );

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ProfileRoute {
  const ProfileRoute();

  static const Object page = Object();
}
