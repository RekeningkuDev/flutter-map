// Stand-ins so the fixture reads like auto_route without a generated .gr.dart.

class RootStackRouter {
  const RootStackRouter();
}

class AutoRouterConfig {
  const AutoRouterConfig({this.replaceInRouteName});

  final String? replaceInRouteName;
}

class AutoRoute {
  const AutoRoute({
    this.path,
    this.page,
    this.initial = false,
    this.children,
    this.fullscreenDialog = false,
    this.guards,
  });

  final String? path;
  final Object? page;
  final bool initial;
  final List<AutoRoute>? children;
  final bool fullscreenDialog;
  final List<Object>? guards;
}

/// Subclass of [AutoRoute]; apps often use one of these exclusively.
class AdaptiveRoute extends AutoRoute {
  const AdaptiveRoute({
    super.path,
    super.page,
    super.initial,
    super.children,
    super.fullscreenDialog,
    super.guards,
  });
}

class CustomRoute extends AutoRoute {
  const CustomRoute({
    super.path,
    super.page,
    super.children,
    super.fullscreenDialog,
  });
}

class RedirectRoute extends AutoRoute {
  const RedirectRoute({super.path, this.redirectTo});

  final String? redirectTo;
}

class RoutePage {
  const RoutePage({this.name});

  final String? name;
}

class AuthGuard {
  const AuthGuard();
}
