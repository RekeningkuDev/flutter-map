import 'package:demo_auto_route_indirect/app_router.dart';
import 'package:flutter/material.dart';

/// Parameterised path, with inline children below an indirect parent.
@RoutePage()
class DetailMain extends StatelessWidget {
  const DetailMain({super.key});

  static const routeName = '/detail/:id';

  static AutoRoute route({required AuthGuard authGuard}) => AdaptiveRoute(
        page: DetailRoute.page,
        path: routeName,
        guards: <Object>[authGuard],
        children: <AutoRoute>[
          AdaptiveRoute(
            page: DetailOverviewRoute.page,
            path: '',
            initial: true,
          ),
          AdaptiveRoute(page: DetailEditRoute.page, path: 'edit'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}

@RoutePage()
class DetailOverviewPage extends StatelessWidget {
  const DetailOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}

@RoutePage()
class DetailEditPage extends StatelessWidget {
  const DetailEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Placeholder());
  }
}
