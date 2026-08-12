import 'dart:io';

import 'package:flutter_map_parser/src/detect.dart';
import 'package:flutter_map_parser/src/edges.dart';
import 'package:flutter_map_parser/src/hints.dart';
import 'package:flutter_map_parser/src/model.dart';
import 'package:flutter_map_parser/src/modes/auto_route.dart';
import 'package:flutter_map_parser/src/modes/go_router.dart';
import 'package:flutter_map_parser/src/modes/go_router_builder.dart';
import 'package:flutter_map_parser/src/modes/navigator_1.dart';
import 'package:flutter_map_parser/src/modes/navigator_2.dart';
import 'package:flutter_map_parser/src/scheme.dart';
import 'package:path/path.dart' as p;

/// Parses a Flutter project into an expo-map-compatible [RouteGraph].
RouteGraph parseProject(String projectRoot) {
  final String resolvedRoot = p.normalize(p.absolute(projectRoot));
  final RoutingMode mode = detectRoutingMode(resolvedRoot);
  if (mode == RoutingMode.unknown) {
    throw StateError(
      'No supported Flutter router found in $resolvedRoot '
      '(looked for GoRouter / go_router_builder / auto_route / '
      'Navigator / Navigator 2).',
    );
  }
  final List<RouteNode> routes;
  final List<LayoutNode> layouts;
  final String? routerFile;
  List<Edge> extraEdges = <Edge>[];
  switch (mode) {
    case RoutingMode.goRouterBuilder:
      final GoRouterBuilderParseResult parsed =
          parseGoRouterBuilderProject(resolvedRoot);
      routes = parsed.routes;
      layouts = parsed.layouts;
      routerFile = parsed.routerFile;
      if (routes.isEmpty) {
        throw StateError(
          'go_router_builder was detected but no @TypedGoRoute entries were found.',
        );
      }
    case RoutingMode.autoRoute:
      final AutoRouteParseResult parsed = parseAutoRouteProject(resolvedRoot);
      routes = parsed.routes;
      layouts = parsed.layouts;
      routerFile = parsed.routerFile;
      if (routes.isEmpty) {
        throw StateError(
          'auto_route was detected but no AutoRoute entries were found.',
        );
      }
      // A silently dropped entry is indistinguishable from a smaller app.
      for (final String entry in parsed.unresolvedEntries) {
        stderr.writeln('warning: unresolved routes entry: $entry');
      }
    case RoutingMode.goRouter:
      final GoRouterParseResult parsed = parseGoRouterProject(resolvedRoot);
      routes = parsed.routes;
      layouts = parsed.layouts;
      routerFile = parsed.routerFile;
      if (routes.isEmpty) {
        throw StateError(
          'GoRouter was detected but no GoRoute entries were found.',
        );
      }
    case RoutingMode.navigator:
      final NavigatorParseResult parsed = parseNavigatorProject(resolvedRoot);
      routes = parsed.routes;
      layouts = parsed.layouts;
      routerFile = parsed.routerFile;
      if (routes.isEmpty) {
        throw StateError(
          'Navigator was detected but no named routes / onGenerateRoute '
          'entries were found.',
        );
      }
    case RoutingMode.navigator2:
      final Navigator2ParseResult parsed =
          parseNavigator2Project(resolvedRoot);
      routes = parsed.routes;
      layouts = parsed.layouts;
      routerFile = parsed.routerFile;
      extraEdges = parsed.stackEdges;
      if (routes.isEmpty) {
        throw StateError(
          'Navigator 2 was detected but no RouterDelegate pages were found.',
        );
      }
    case RoutingMode.unknown:
      throw StateError('Unsupported routing mode.');
  }
  applyHintsToRoutes(routes: routes, projectRoot: resolvedRoot);
  final List<Edge> edges = <Edge>[
    ...extractEdges(
      projectRoot: resolvedRoot,
      routes: routes,
    ),
    ...extraEdges,
  ];
  final String? scheme = readDeepLinkScheme(resolvedRoot);
  return RouteGraph(
    generatedAt: DateTime.now().toUtc().toIso8601String(),
    projectRoot: resolvedRoot,
    scheme: scheme,
    deepLinkTemplates: buildDeepLinkTemplates(scheme),
    mode: routingModeLabel(mode),
    layouts: layouts,
    routes: routes,
    edges: edges,
    extras: <String, Object?>{
      if (routerFile != null) 'routerFile': routerFile,
    },
  );
}
