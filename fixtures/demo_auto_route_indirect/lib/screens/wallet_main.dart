import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// Getter form, nested under the shell route.
@RoutePage()
class WalletMain extends StatelessWidget {
  const WalletMain({super.key});

  static const routeName = 'wallet';

  static AutoRoute get route => AdaptiveRoute(
        page: WalletRoute.page,
        path: routeName,
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
