import 'auto_route_stubs.dart';
import 'screens/about_main.dart';
import 'screens/details_main.dart';
import 'screens/legacy_main.dart';
import 'screens/settings_main.dart';
import 'screens/shell_main.dart';

/// Router that keeps route declarations next to their screens, so every entry
/// here is an indirect reference rather than an inline `AutoRoute(...)`.
@AutoRouterConfig(replaceInRouteName: 'Main,Route')
class AppRouter extends RootStackRouter {
  final AuthGuard authGuard = const AuthGuard();

  @override
  List<AutoRoute> get routes => <AutoRoute>[
        // `static AutoRoute route({...}) => ...` reached with arguments.
        ShellMain.route(authGuard: authGuard),
        // `static final AutoRoute route = ...` reached as a bare reference.
        AboutMain.route,
        // `static AutoRoute get route => ...` reached as a bare reference.
        SettingsMain.route,
        // Parameterised path held in a non-const `static String`.
        DetailsMain.route,
        // Self-referential member: must be dropped, not recursed into.
        LegacyMain.route,
        // The same shell referenced twice: one route node, one layout node.
        ShellMain.route(authGuard: authGuard),
        // Redirects are not screens.
        const RedirectRoute(path: '/old-about', redirectTo: '/about'),
      ];
}
