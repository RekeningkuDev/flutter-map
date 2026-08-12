import 'dart:io';

import 'package:flutter_map_parser/flutter_map_parser.dart';
import 'package:flutter_map_parser/src/modes/auto_route.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Covers routers that reference per-screen `route` members instead of
/// declaring `AutoRoute(...)` inline. Real apps overwhelmingly do this, and
/// every entry was previously dropped.
void main() {
  final String fixtureRoot = p.normalize(
    p.join(
      Directory.current.path,
      '..',
      '..',
      'fixtures',
      'demo_auto_route_indirect',
    ),
  );

  test('detects auto_route mode for the indirect fixture', () {
    expect(detectRoutingMode(fixtureRoot), RoutingMode.autoRoute);
  });

  test('resolves indirect route references in all declaration forms', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    expect(graph.mode, 'auto_route');
    expect(
      graph.routes.map((RouteNode route) => route.id).toSet(),
      equals(<String>{
        'ShellRoute',
        'HomeRoute',
        'InboxRoute',
        'ProfileRoute',
        'AboutRoute',
        'SettingsRoute',
        'DetailsRoute',
      }),
    );
  });

  test('resolves paths held in identifiers rather than literals', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    final Map<String, String> paths = <String, String>{
      for (final RouteNode route in graph.routes) route.id: route.urlPath,
    };
    // `static AutoRoute route({...}) => AdaptiveRoute(path: routeName)`
    expect(paths['ShellRoute'], '/');
    // `static AutoRoute get route => CustomRoute(path: routeName)`
    expect(paths['SettingsRoute'], '/settings');
    // `static final AutoRoute route = AdaptiveRoute(path: routeName)`
    expect(paths['AboutRoute'], '/about');
    // Non-const `static String routeName`, which a const-only resolver misses.
    expect(paths['DetailsRoute'], '/details/:id');
  });

  test('follows children declared behind an indirect reference', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    final Map<String, String> paths = <String, String>{
      for (final RouteNode route in graph.routes) route.id: route.urlPath,
    };
    // Relative child path joins onto the shell's path.
    expect(paths['HomeRoute'], '/home');
    // Absolute child path escapes it.
    expect(paths['ProfileRoute'], '/profile');
    // The shell is referenced twice by the router, so this also pins that a
    // repeated reference does not duplicate the layout.
    expect(graph.layouts, hasLength(1));
    // The layout is declared in the screen file, not the router.
    expect(graph.layouts.single.file, 'lib/screens/shell_main.dart');
  });

  test('emits one route per id when a reference is repeated', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    final Iterable<RouteNode> shells = graph.routes.where(
      (RouteNode route) => route.id == 'ShellRoute',
    );
    expect(shells, hasLength(1));
  });

  test('attributes routes to the file that declared them', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    for (final RouteNode route in graph.routes) {
      expect(
        route.file,
        isNot(contains('app_router.dart')),
        reason: '${route.id} should resolve to its screen file',
      );
    }
    final RouteNode details = graph.routes.firstWhere(
      (RouteNode route) => route.id == 'DetailsRoute',
    );
    expect(details.file, 'lib/screens/details_main.dart');
    expect(details.params, equals(<String>['id']));
  });

  test('attributes an inline child to its own page class, not the shell', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    final RouteNode inbox = graph.routes.firstWhere(
      (RouteNode route) => route.id == 'InboxRoute',
    );
    // `InboxMain` is named by neither the Page nor the Screen convention, so
    // this only resolves if the router's `replaceInRouteName` is applied.
    expect(inbox.file, 'lib/screens/inbox_main.dart');
    expect(inbox.widgetName, 'InboxScreen');
    expect(inbox.urlPath, '/inbox');
  });

  test('does not leak a layout onto later siblings', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    // `/about` is declared after the shell but is not inside it.
    final RouteNode about = graph.routes.firstWhere(
      (RouteNode route) => route.id == 'AboutRoute',
    );
    expect(about.layoutDir, isEmpty);
  });

  test('reads AutoRoute subclasses and skips redirects', () {
    final RouteGraph graph = parseProject(fixtureRoot);
    final RouteNode settings = graph.routes.firstWhere(
      (RouteNode route) => route.id == 'SettingsRoute',
    );
    // CustomRoute(fullscreenDialog: true)
    expect(settings.presentation, 'modal');
    expect(
      graph.routes.any((RouteNode route) => route.urlPath == '/old-about'),
      isFalse,
    );
  });

  test('drops a self-referential route member and reports it', () {
    final AutoRouteParseResult result = parseAutoRouteProject(fixtureRoot);
    expect(
      result.routes.any((RouteNode route) => route.id.startsWith('Legacy')),
      isFalse,
    );
    expect(result.unresolvedEntries, equals(<String>['LegacyMain.route']));
  });
}
