import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

/// A member that resolves back to itself. Must be dropped rather than sending
/// the reference resolver into infinite recursion.
@RoutePage()
class LegacyMain extends StatelessWidget {
  const LegacyMain({super.key});

  static AutoRoute get route => LegacyMain.route;

  @override
  Widget build(BuildContext context) => const Scaffold();
}
