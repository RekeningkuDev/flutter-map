import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// `CycleMain.route` and `LoopMain.route` point at each other. Following the
/// reference must terminate and drop the entry rather than recurse forever.
@RoutePage()
class CycleMain extends StatelessWidget {
  const CycleMain({super.key});

  static const routeName = '/cycle';

  static AutoRoute get route => LoopMain.route;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}

class LoopMain {
  const LoopMain();

  static AutoRoute get route => CycleMain.route;
}
