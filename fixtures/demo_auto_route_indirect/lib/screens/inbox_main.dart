import 'package:flutter/material.dart';

import '../auto_route_stubs.dart';

/// Page class with no `route` member of its own: its route is declared inline
/// inside the shell, so `page:` is the only thing tying the two together.
///
/// The class name follows neither the `Page` nor the `Screen` convention, so
/// binding it back to `InboxRoute` requires the router's `replaceInRouteName`.
@RoutePage()
class InboxMain extends StatelessWidget {
  const InboxMain({super.key});

  @override
  Widget build(BuildContext context) => const InboxScreen();
}

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class InboxRoute {
  const InboxRoute();

  static const Object page = Object();
}
