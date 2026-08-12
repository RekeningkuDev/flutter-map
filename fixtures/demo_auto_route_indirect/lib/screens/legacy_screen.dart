import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// `routeName` is a plain mutable static, so it never reaches the compile-time
/// constant table; the parser still has to recover the literal.
@RoutePage()
class LegacyScreen extends StatelessWidget {
  const LegacyScreen({super.key});

  static String routeName = '/legacy';

  static AutoRoute get route => AdaptiveRoute(
        page: LegacyRoute.page,
        path: routeName,
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
