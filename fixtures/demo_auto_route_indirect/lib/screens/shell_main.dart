import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';
import 'home_main.dart';
import 'inbox_main.dart';
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
          // Declared inline rather than as a `route` member on the child's own
          // page class, so the enclosing class is `ShellMain` and only `page:`
          // says which screen this route actually belongs to.
          const AdaptiveRoute(page: InboxRoute.page, path: 'inbox'),
        ],
      );

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ShellRoute {
  const ShellRoute();

  static const Object page = Object();
}
