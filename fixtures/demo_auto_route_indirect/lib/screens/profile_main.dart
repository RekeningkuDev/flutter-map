import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// Field form with an explicit `AutoRoute` type annotation.
@RoutePage()
class ProfileMain extends StatelessWidget {
  const ProfileMain({super.key});

  static const routeName = '/profile';

  static final AutoRoute route = AdaptiveRoute(
    page: ProfileRoute.page,
    path: routeName,
  );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
