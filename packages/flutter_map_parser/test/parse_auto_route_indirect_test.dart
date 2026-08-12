import 'dart:io';

import 'package:flutter_map_parser/flutter_map_parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

  late RouteGraph graph;
  late Map<String, RouteNode> byId;

  setUpAll(() {
    graph = parseProject(fixtureRoot);
    byId = <String, RouteNode>{
      for (final RouteNode route in graph.routes) route.id: route,
    };
  });

  test('detects auto_route mode for the indirect fixture', () {
    expect(detectRoutingMode(fixtureRoot), RoutingMode.autoRoute);
  });

  test('resolves route tables built from indirect `X.route` references', () {
    expect(graph.mode, 'auto_route');
    expect(
      byId.keys.toSet(),
      equals(<String>{
        'AppRoute',
        'HomeRoute',
        'WalletRoute',
        'ProfileRoute',
        'SettingsRoute',
        'LegacyRoute',
        'DetailRoute',
        'DetailOverviewRoute',
        'DetailEditRoute',
        'PlainRoute',
      }),
    );
  });

  test('handles all three `route` member declaration forms', () {
    // `static AutoRoute route(...) => AdaptiveRoute(...)`
    expect(byId['AppRoute']!.urlPath, '/');
    // `static final route = AdaptiveRoute(...)` (no type annotation)
    expect(byId['HomeRoute']!.urlPath, '/home');
    // `static AutoRoute get route => AdaptiveRoute(...)`
    expect(byId['SettingsRoute']!.urlPath, '/settings');
    // `static final AutoRoute route = AdaptiveRoute(...)`
    expect(byId['ProfileRoute']!.urlPath, '/profile');
  });

  test('binds routes back to the file that declared them', () {
    expect(byId['ProfileRoute']!.file, 'lib/screens/profile_main.dart');
    expect(byId['HomeRoute']!.file, 'lib/screens/home_main.dart');
    expect(byId['LegacyRoute']!.file, 'lib/screens/legacy_screen.dart');
    expect(byId['PlainRoute']!.file, 'lib/screens/plain_page.dart');
  });

  test('reaches nested children through an indirect reference', () {
    expect(byId['HomeRoute']!.layoutDir, '');
    expect(byId['WalletRoute']!.urlPath, '/wallet');
    expect(
      graph.layouts.map((LayoutNode layout) => layout.dir).toSet(),
      contains('/detail/:id'),
    );
    expect(byId['DetailEditRoute']!.urlPath, '/detail/:id/edit');
    // An empty child path collapses onto its parent.
    expect(byId['DetailOverviewRoute']!.urlPath, '/detail/:id');
  });

  test('resolves `path:` constants and path params', () {
    expect(byId['DetailRoute']!.urlPath, '/detail/:id');
    expect(byId['DetailRoute']!.params, equals(<String>['id']));
    expect(byId['DetailEditRoute']!.params, equals(<String>['id']));
  });

  test('recovers a path held in a non-const `static String`', () {
    expect(byId['LegacyRoute']!.urlPath, '/legacy');
  });

  test('keeps reading AdaptiveRoute arguments the base class supports', () {
    expect(byId['SettingsRoute']!.presentation, 'modal');
  });

  test('drops mutually recursive `route` members instead of looping', () {
    expect(byId.containsKey('CycleRoute'), isFalse);
  });
}
