import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

/// `routeName` is a plain mutable static, which a const-only resolver misses.
@RoutePage()
class DetailsMain extends StatelessWidget {
  const DetailsMain({super.key});

  static String routeName = '/details/:id';

  static AutoRoute route = AdaptiveRoute(
    page: DetailsRoute.page,
    path: routeName,
  );

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class DetailsRoute {
  const DetailsRoute();

  static const Object page = Object();
}
