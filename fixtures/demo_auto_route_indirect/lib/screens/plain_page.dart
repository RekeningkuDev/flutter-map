import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// Declared inline in the router, the way the upstream fixtures do it.
@RoutePage()
class PlainPage extends StatelessWidget {
  const PlainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
