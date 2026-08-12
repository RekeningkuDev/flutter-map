import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';
import 'home_main.dart';
import 'profile_main.dart';

/// Tab shell whose children are declared here, not in the router, so the
/// children list is only reachable through the indirect reference.
@RoutePage()
class ShellMain extends StatelessWidget {
  const ShellMain({super.key});

  static const String routeName = '/';

  static AutoRoute route({required AuthGuard authGuard}) => AdaptiveRoute(
        page: ShellRoute.page,
        path: routeName,
        initial: true,
        guards: <Object>[authGuard],
        children: <AutoRoute>[
          HomeMain.route,
          ProfileMain.route,
        ],
      );

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ShellRoute {
  const ShellRoute();

  static const Object page = Object();
}
