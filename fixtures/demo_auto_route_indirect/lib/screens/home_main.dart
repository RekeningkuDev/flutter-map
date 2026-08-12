import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// Field form without an explicit `AutoRoute` type annotation.
@RoutePage()
class HomeMain extends StatelessWidget {
  const HomeMain({super.key});

  static const routeName = 'home';

  static final route = AdaptiveRoute(
    page: HomeRoute.page,
    path: routeName,
  );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
