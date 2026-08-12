import 'package:demo_auto_route_indirect/screens/app_main.dart';
import 'package:demo_auto_route_indirect/screens/cycle_main.dart';
import 'package:demo_auto_route_indirect/screens/detail_main.dart';
import 'package:demo_auto_route_indirect/screens/legacy_screen.dart';
import 'package:demo_auto_route_indirect/screens/plain_page.dart';
import 'package:demo_auto_route_indirect/screens/profile_main.dart';
import 'package:demo_auto_route_indirect/screens/settings_main.dart';

/// Route table built from per-screen `route` members rather than inline
/// `AutoRoute(...)` constructors, which is how large auto_route apps keep the
/// router file from growing without bound.
@AutoRouterConfig(replaceInRouteName: 'Main|Page|Screen,Route')
class AppRouter extends RootStackRouter {
  final AuthGuard authGuard = const AuthGuard();

  @override
  List<AutoRoute> get routes => <AutoRoute>[
        // Method form, with children reached through further indirection.
        AppMain.route(authGuard: authGuard),
        // Field form, referenced as a bare `X.route`.
        ProfileMain.route,
        // Getter form.
        SettingsMain.route,
        // Path held in a non-const `static String`.
        LegacyScreen.route,
        // Parameterised path plus inline children.
        DetailMain.route(authGuard: authGuard),
        // Mutually recursive `route` members; must be dropped, not followed.
        CycleMain.route,
        // Inline declaration still works alongside the indirect ones.
        AutoRoute(path: '/plain', page: PlainRoute.page),
      ];
}

// Stand-ins so the fixture reads like auto_route without generated .gr.dart.
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
    this.guards,
    this.fullscreenDialog = false,
  });

  final String? path;
  final Object? page;
  final bool initial;
  final List<AutoRoute>? children;
  final List<Object>? guards;
  final bool fullscreenDialog;
}

class AdaptiveRoute extends AutoRoute {
  const AdaptiveRoute({
    super.path,
    super.page,
    super.initial,
    super.children,
    super.guards,
    super.fullscreenDialog,
  });
}

class AuthGuard {
  const AuthGuard();
}

class RoutePage {
  const RoutePage({this.name});

  final String? name;
}

class AppRoute {
  const AppRoute();
  static const Object page = Object();
}

class HomeRoute {
  const HomeRoute();
  static const Object page = Object();
}

class WalletRoute {
  const WalletRoute();
  static const Object page = Object();
}

class ProfileRoute {
  const ProfileRoute();
  static const Object page = Object();
}

class SettingsRoute {
  const SettingsRoute();
  static const Object page = Object();
}

class LegacyRoute {
  const LegacyRoute();
  static const Object page = Object();
}

class DetailRoute {
  const DetailRoute({required this.id});
  final String id;
  static const Object page = Object();
}

class DetailOverviewRoute {
  const DetailOverviewRoute();
  static const Object page = Object();
}

class DetailEditRoute {
  const DetailEditRoute();
  static const Object page = Object();
}

class CycleRoute {
  const CycleRoute();
  static const Object page = Object();
}

class PlainRoute {
  const PlainRoute();
  static const Object page = Object();
}
