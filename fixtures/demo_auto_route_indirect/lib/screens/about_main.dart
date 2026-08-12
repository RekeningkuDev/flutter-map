import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

@RoutePage()
class AboutMain extends StatelessWidget {
  const AboutMain({super.key});

  static const String routeName = '/about';

  static final AutoRoute route = AdaptiveRoute(
    page: AboutRoute.page,
    path: routeName,
  );

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class AboutRoute {
  const AboutRoute();

  static const Object page = Object();
}
