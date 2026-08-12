import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:demo_auto_route_indirect/screens/home_main.dart';
import 'package:demo_auto_route_indirect/screens/wallet_main.dart';
import 'package:flutter/material.dart';

/// Shell route: method form, children declared as further indirect references.
@RoutePage()
class AppMain extends StatelessWidget {
  const AppMain({super.key});

  static const routeName = '/';

  static AutoRoute route({required AuthGuard authGuard}) => AdaptiveRoute(
        page: AppRoute.page,
        path: routeName,
        initial: true,
        guards: <Object>[authGuard],
        children: <AutoRoute>[
          HomeMain.route,
          WalletMain.route,
        ],
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
