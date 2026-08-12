import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_map_parser/src/const_strings.dart';
import 'package:flutter_map_parser/src/model.dart';
import 'package:path/path.dart' as p;

/// Constructors that produce an `AutoRoute`.
///
/// `AutoRoute` is routinely subclassed, and apps often use a subclass
/// exclusively, so matching on `AutoRoute` alone finds nothing.
const Set<String> _routeConstructorNames = <String>{
  'AutoRoute',
  'AdaptiveRoute',
  'CustomRoute',
  'MaterialRoute',
  'CupertinoRoute',
};

/// Result of parsing `@AutoRouterConfig` route tables.
class AutoRouteParseResult {
  const AutoRouteParseResult({
    required this.routes,
    required this.layouts,
    required this.routerFile,
    this.unresolvedEntries = const <String>[],
  });

  final List<RouteNode> routes;
  final List<LayoutNode> layouts;
  final String? routerFile;

  /// Source text of `routes` entries that could not be resolved to a route.
  ///
  /// Surfaced for diagnostics: a silently dropped entry is indistinguishable
  /// from an app that genuinely has fewer routes.
  final List<String> unresolvedEntries;
}

/// Parses auto_route `@AutoRouterConfig` routers under [projectRoot]/lib.
AutoRouteParseResult parseAutoRouteProject(String projectRoot) {
  final List<_DartUnit> units = _loadDartUnits(projectRoot);
  final _RoutePageIndex routePageFiles = _collectRoutePageFiles(
    projectRoot: projectRoot,
    units: units,
  );
  final _ProjectIndex index = _ProjectIndex.build(units);
  final List<RouteNode> routes = <RouteNode>[];
  final List<LayoutNode> layouts = <LayoutNode>[];
  final List<String> unresolved = <String>[];
  String? routerFile;
  final Set<String> seenIds = <String>{};
  for (final _DartUnit unit in units) {
    for (final ClassDeclaration declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      final Annotation? config = _findAnnotation(
        declaration,
        <String>{'AutoRouterConfig'},
      );
      if (config == null) {
        continue;
      }
      routerFile ??= _relative(projectRoot, unit.filePath);
      final Expression? routesExpression =
          _findRoutesExpression(declaration);
      if (routesExpression == null) {
        continue;
      }
      _walkAutoRoutes(
        expression: routesExpression,
        parentPath: '',
        projectRoot: projectRoot,
        routePageFiles: routePageFiles,
        routes: routes,
        layouts: layouts,
        seenIds: seenIds,
        routerFile: routerFile,
        index: index,
        contextUnit: unit,
        contextClassName: declaration.name.lexeme,
        unresolved: unresolved,
      );
    }
  }
  return AutoRouteParseResult(
    routes: routes,
    layouts: layouts,
    routerFile: routerFile,
    unresolvedEntries: unresolved,
  );
}

void _walkAutoRoutes({
  required Expression expression,
  required String parentPath,
  required String projectRoot,
  required _RoutePageIndex routePageFiles,
  required List<RouteNode> routes,
  required List<LayoutNode> layouts,
  required Set<String> seenIds,
  required String routerFile,
  required _ProjectIndex index,
  required _DartUnit contextUnit,
  required String? contextClassName,
  required List<String> unresolved,
  String parentLayoutDir = '',
  String parentNavigator = 'stack',
}) {
  final ListLiteral? list = expression is ListLiteral ? expression : null;
  if (list == null) {
    return;
  }
  for (final CollectionElement element in list.elements) {
    if (element is! Expression) {
      unresolved.add(element.toSource());
      continue;
    }
    final _ResolvedRoute? resolved = _resolveRouteExpression(
      expression: element,
      index: index,
      contextUnit: contextUnit,
      ownerClassName: contextClassName,
      visiting: <String>{},
    );
    if (resolved == null) {
      if (_asRouteCall(element)?.name != 'RedirectRoute') {
        unresolved.add(element.toSource());
      }
      continue;
    }
    final _RouteCall call = resolved.call;
    final String? pageType = _pageTypeName(call.argumentList);
    final String? rawPath = _stringNamedArg(
      call.argumentList,
      'path',
      constStrings: resolved.constStrings,
      className: resolved.ownerClassName,
      ownerClass: resolved.declaringClass,
    );
    final bool initial = _boolNamedArg(call.argumentList, 'initial') ?? false;
    final String absolutePath = _resolveAbsolutePath(
      parentPath: parentPath,
      rawPath: rawPath,
      pageType: pageType,
      initial: initial,
    );
    final String id = pageType ?? _slugFromPath(absolutePath);
    final Expression? children = _namedArg(call.argumentList, 'children');
    final bool hasChildren = children is ListLiteral && children.elements.isNotEmpty;
    final String ownLayoutDir = absolutePath == '/' ? '' : absolutePath;
    if (hasChildren) {
      layouts.add(
        LayoutNode(
          file: resolved.declaringUnit == null
              ? routerFile
              : _relative(projectRoot, resolved.declaringUnit!.filePath),
          dir: ownLayoutDir,
          navigator: 'stack',
        ),
      );
    }
    if (seenIds.add(id)) {
      // Prefer the class that declared this route: we followed the reference to
      // get here, so it is authoritative. Falling back to the route id relies
      // on reproducing auto_route's page-class-to-route-name mangling, which
      // does not hold for every naming convention.
      final _RoutePageBinding? binding =
          routePageFiles.byClassName[resolved.ownerClassName] ??
              routePageFiles.byRouteId[id];
      final String file = binding?.file ??
          _guessPageFile(projectRoot, id) ??
          routerFile;
      routes.add(
        RouteNode(
          id: id,
          urlPath: absolutePath.isEmpty ? '/' : absolutePath,
          file: file,
          slug: _slugFromPath(absolutePath.isEmpty ? '/' : absolutePath),
          params: _paramsFromPath(absolutePath),
          navigator: hasChildren ? 'stack' : parentNavigator,
          // The enclosing layout, not whichever layout happened to be appended
          // last: sibling routes declared after a shell must not inherit it.
          layoutDir: parentLayoutDir,
          presentation: _presentation(call.argumentList),
          widgetName: binding?.widgetName,
        ),
      );
    }
    if (children != null) {
      _walkAutoRoutes(
        expression: children,
        parentPath: absolutePath,
        projectRoot: projectRoot,
        routePageFiles: routePageFiles,
        routes: routes,
        layouts: layouts,
        seenIds: seenIds,
        routerFile: routerFile,
        index: index,
        // Children are declared alongside the route we just resolved, so bare
        // constants in them resolve against that class's unit, not the router's.
        contextUnit: resolved.declaringUnit ?? contextUnit,
        contextClassName: resolved.ownerClassName,
        unresolved: unresolved,
        parentLayoutDir: ownLayoutDir,
        parentNavigator: 'stack',
      );
    }
  }
}

/// Indexes every class in the project so indirect route references can be
/// followed without re-reading files.
class _ProjectIndex {
  _ProjectIndex(this._classes);

  final Map<String, _ClassContext> _classes;
  final Map<String, ConstStringTable> _constCache = <String, ConstStringTable>{};

  static _ProjectIndex build(List<_DartUnit> units) {
    final Map<String, _ClassContext> classes = <String, _ClassContext>{};
    for (final _DartUnit unit in units) {
      for (final ClassDeclaration declaration
          in unit.unit.declarations.whereType<ClassDeclaration>()) {
        classes.putIfAbsent(
          declaration.name.lexeme,
          () => _ClassContext(declaration: declaration, unit: unit),
        );
      }
    }
    return _ProjectIndex(classes);
  }

  _ClassContext? lookup(String className) => _classes[className];

  ConstStringTable constsFor(_DartUnit unit) {
    return _constCache.putIfAbsent(
      unit.filePath,
      () => ConstStringTable.fromUnit(unit.unit),
    );
  }
}

class _ClassContext {
  const _ClassContext({required this.declaration, required this.unit});

  final ClassDeclaration declaration;
  final _DartUnit unit;
}

/// A route constructor call plus the scope its arguments must be read in.
class _ResolvedRoute {
  const _ResolvedRoute({
    required this.call,
    required this.constStrings,
    this.ownerClassName,
    this.declaringUnit,
    this.declaringClass,
  });

  final _RouteCall call;

  /// Constants of the unit that declared the route, for `path: routeName`.
  final ConstStringTable constStrings;

  /// Class that declared the route, e.g. `PortfolioMain` for `PortfolioMain.route`.
  final String? ownerClassName;

  final _DartUnit? declaringUnit;

  final ClassDeclaration? declaringClass;
}

/// Returns the string literal a static field of [declaration] is initialised to.
///
/// [ConstStringTable] deliberately only tracks `const`/`final` declarations, but
/// route paths are sometimes held in a plain `static String routeName = '...'`,
/// which is still a literal for our purposes.
String? _staticStringField(ClassDeclaration declaration, String name) {
  for (final ClassMember member in declaration.members) {
    if (member is! FieldDeclaration || !member.isStatic) {
      continue;
    }
    for (final VariableDeclaration variable in member.fields.variables) {
      if (variable.name.lexeme != name) {
        continue;
      }
      final Expression? initializer = variable.initializer;
      if (initializer is SimpleStringLiteral) {
        return initializer.value;
      }
      if (initializer is AdjacentStrings) {
        return initializer.stringValue;
      }
    }
  }
  return null;
}

/// Resolves a `routes` list element to the route constructor it stands for.
///
/// Handles a direct constructor call as well as the indirect forms apps use to
/// keep route declarations next to their screens: `X.route` and `X.route(...)`.
_ResolvedRoute? _resolveRouteExpression({
  required Expression expression,
  required _ProjectIndex index,
  required _DartUnit contextUnit,
  required String? ownerClassName,
  required Set<String> visiting,
  ClassDeclaration? ownerClass,
}) {
  final _RouteCall? direct = _asRouteCall(expression);
  if (direct != null) {
    if (_routeConstructorNames.contains(direct.name)) {
      return _ResolvedRoute(
        call: direct,
        constStrings: index.constsFor(contextUnit),
        ownerClassName: ownerClassName,
        declaringUnit: contextUnit,
        declaringClass: ownerClass,
      );
    }
    if (direct.name == 'RedirectRoute') {
      return null;
    }
  }
  // `X.route(authGuard: ...)`
  if (expression is MethodInvocation) {
    final Expression? target = expression.target;
    if (target is SimpleIdentifier) {
      return _resolveClassMember(
        className: target.name,
        memberName: expression.methodName.name,
        index: index,
        visiting: visiting,
      );
    }
  }
  // `X.route`
  if (expression is PrefixedIdentifier) {
    return _resolveClassMember(
      className: expression.prefix.name,
      memberName: expression.identifier.name,
      index: index,
      visiting: visiting,
    );
  }
  if (expression is PropertyAccess) {
    final Expression? target = expression.target;
    if (target is SimpleIdentifier) {
      return _resolveClassMember(
        className: target.name,
        memberName: expression.propertyName.name,
        index: index,
        visiting: visiting,
      );
    }
  }
  return null;
}

_ResolvedRoute? _resolveClassMember({
  required String className,
  required String memberName,
  required _ProjectIndex index,
  required Set<String> visiting,
}) {
  final String key = '$className.$memberName';
  // A member that resolves back to itself must be dropped, not recursed into.
  if (!visiting.add(key)) {
    return null;
  }
  try {
    final _ClassContext? context = index.lookup(className);
    if (context == null) {
      return null;
    }
    final Expression? expression = _classMemberExpression(
      context.declaration,
      memberName,
    );
    if (expression == null) {
      return null;
    }
    return _resolveRouteExpression(
      expression: expression,
      index: index,
      contextUnit: context.unit,
      ownerClassName: className,
      visiting: visiting,
      ownerClass: context.declaration,
    );
  } finally {
    visiting.remove(key);
  }
}

/// Returns the expression a `route` member evaluates to.
///
/// Covers the three shapes apps declare it in: a method
/// (`static AutoRoute route(...) => ...`), a getter
/// (`static AutoRoute get route => ...`) and a field
/// (`static final AutoRoute route = ...`).
Expression? _classMemberExpression(
  ClassDeclaration declaration,
  String memberName,
) {
  for (final ClassMember member in declaration.members) {
    if (member is MethodDeclaration && member.name.lexeme == memberName) {
      return _getterExpression(member);
    }
  }
  for (final ClassMember member in declaration.members) {
    if (member is! FieldDeclaration) {
      continue;
    }
    for (final VariableDeclaration variable in member.fields.variables) {
      if (variable.name.lexeme == memberName) {
        return variable.initializer;
      }
    }
  }
  return null;
}

String _resolveAbsolutePath({
  required String parentPath,
  required String? rawPath,
  required String? pageType,
  required bool initial,
}) {
  if (rawPath != null) {
    if (rawPath.isEmpty) {
      return parentPath.isEmpty ? '/' : parentPath;
    }
    return _joinPaths(parentPath, rawPath);
  }
  if (initial && (parentPath.isEmpty || parentPath == '/')) {
    return '/';
  }
  if (pageType != null) {
    final String leaf = _routeNameToPathLeaf(pageType);
    return _joinPaths(parentPath, leaf);
  }
  return parentPath.isEmpty ? '/' : parentPath;
}

String _routeNameToPathLeaf(String routeTypeName) {
  String name = routeTypeName;
  if (name.endsWith('Route')) {
    name = name.substring(0, name.length - 'Route'.length);
  }
  if (name.isEmpty) {
    return '/';
  }
  final StringBuffer buffer = StringBuffer()
    ..write(name[0].toLowerCase())
    ..write(name.substring(1));
  return buffer.toString().replaceAllMapped(
        RegExp(r'[A-Z]'),
        (Match match) => '-${match.group(0)!.toLowerCase()}',
      );
}

String? _presentation(ArgumentList argumentList) {
  final bool? fullscreenDialog =
      _boolNamedArg(argumentList, 'fullscreenDialog');
  if (fullscreenDialog == true) {
    return 'modal';
  }
  return null;
}

String? _pageTypeName(ArgumentList argumentList) {
  final Expression? page = _namedArg(argumentList, 'page');
  if (page == null) {
    return null;
  }
  if (page is PrefixedIdentifier) {
    return page.prefix.name;
  }
  if (page is PropertyAccess) {
    final Expression target = page.target!;
    if (target is SimpleIdentifier) {
      return target.name;
    }
    if (target is PrefixedIdentifier) {
      return target.identifier.name;
    }
  }
  if (page is SimpleIdentifier) {
    return page.name;
  }
  return null;
}

MethodDeclaration? _findRoutesGetter(ClassDeclaration declaration) {
  for (final ClassMember member in declaration.members) {
    if (member is MethodDeclaration &&
        member.isGetter &&
        member.name.lexeme == 'routes') {
      return member;
    }
  }
  return null;
}

Expression? _findRoutesExpression(ClassDeclaration declaration) {
  final MethodDeclaration? getter = _findRoutesGetter(declaration);
  if (getter != null) {
    return _getterExpression(getter);
  }
  for (final ClassMember member in declaration.members) {
    if (member is! FieldDeclaration) {
      continue;
    }
    for (final VariableDeclaration variable in member.fields.variables) {
      if (variable.name.lexeme != 'routes') {
        continue;
      }
      return variable.initializer;
    }
  }
  return null;
}

Expression? _getterExpression(MethodDeclaration getter) {
  final FunctionBody body = getter.body;
  if (body is ExpressionFunctionBody) {
    return body.expression;
  }
  if (body is BlockFunctionBody) {
    for (final Statement statement in body.block.statements) {
      if (statement is ReturnStatement) {
        return statement.expression;
      }
    }
  }
  return null;
}

class _RoutePageBinding {
  const _RoutePageBinding({
    required this.file,
    this.widgetName,
  });

  final String file;
  final String? widgetName;
}

/// `@RoutePage()` bindings, keyed both by derived route id and by the
/// annotated class name.
class _RoutePageIndex {
  const _RoutePageIndex({required this.byRouteId, required this.byClassName});

  final Map<String, _RoutePageBinding> byRouteId;
  final Map<String, _RoutePageBinding> byClassName;
}

_RoutePageIndex _collectRoutePageFiles({
  required String projectRoot,
  required List<_DartUnit> units,
}) {
  final Map<String, String> classFiles = <String, String>{};
  for (final _DartUnit unit in units) {
    for (final ClassDeclaration declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      classFiles[declaration.name.lexeme] =
          _relative(projectRoot, unit.filePath);
    }
  }
  final Map<String, _RoutePageBinding> bindings = <String, _RoutePageBinding>{};
  final Map<String, _RoutePageBinding> byClassName =
      <String, _RoutePageBinding>{};
  for (final _DartUnit unit in units) {
    final String pageFile = _relative(projectRoot, unit.filePath);
    for (final ClassDeclaration declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      final Annotation? routePage = _findAnnotation(
        declaration,
        <String>{'RoutePage'},
      );
      if (routePage == null) {
        continue;
      }
      final String className = declaration.name.lexeme;
      final String routeId = _pageClassToRouteId(className);
      final String? childWidget = _extractReturnedWidgetType(declaration);
      final String? childFile =
          childWidget == null ? null : classFiles[childWidget];
      final String resolvedFile;
      if (childFile != null && !_isRouterLikePath(childFile)) {
        resolvedFile = childFile;
      } else if (!_isRouterLikePath(pageFile)) {
        resolvedFile = pageFile;
      } else {
        resolvedFile = childFile ?? pageFile;
      }
      final String? widgetName = childWidget ??
          (className.endsWith('Page') || className.endsWith('Screen')
              ? className
              : null);
      final _RoutePageBinding binding = _RoutePageBinding(
        file: resolvedFile,
        widgetName: widgetName,
      );
      _mergeRoutePageBinding(
        bindings: bindings,
        routeId: routeId,
        binding: binding,
      );
      _mergeRoutePageBinding(
        bindings: byClassName,
        routeId: className,
        binding: binding,
      );
    }
  }
  return _RoutePageIndex(byRouteId: bindings, byClassName: byClassName);
}

void _mergeRoutePageBinding({
  required Map<String, _RoutePageBinding> bindings,
  required String routeId,
  required _RoutePageBinding binding,
}) {
  final _RoutePageBinding? existing = bindings[routeId];
  if (existing == null) {
    bindings[routeId] = binding;
    return;
  }
  final bool existingIsRouter = _isRouterLikePath(existing.file);
  final bool nextIsRouter = _isRouterLikePath(binding.file);
  if (existingIsRouter && !nextIsRouter) {
    bindings[routeId] = binding;
    return;
  }
  if (!existingIsRouter && nextIsRouter) {
    return;
  }
  if (existing.widgetName == null && binding.widgetName != null) {
    bindings[routeId] = _RoutePageBinding(
      file: existing.file,
      widgetName: binding.widgetName,
    );
  }
}

bool _isRouterLikePath(String relativeFile) {
  final String base = p.posix.basename(relativeFile);
  return base == 'router.dart' ||
      base == 'routes.dart' ||
      base == 'app_router.dart' ||
      relativeFile.contains('/routes/');
}

String? _extractReturnedWidgetType(ClassDeclaration declaration) {
  MethodDeclaration? buildMethod;
  for (final ClassMember member in declaration.members) {
    if (member is MethodDeclaration && member.name.lexeme == 'build') {
      buildMethod = member;
      break;
    }
  }
  if (buildMethod == null) {
    return null;
  }
  final FunctionBody body = buildMethod.body;
  Expression? expression;
  if (body is ExpressionFunctionBody) {
    expression = body.expression;
  } else if (body is BlockFunctionBody) {
    for (final Statement statement in body.block.statements) {
      if (statement is ReturnStatement) {
        expression = statement.expression;
        break;
      }
    }
  }
  return _widgetTypeFromExpression(expression);
}

String? _widgetTypeFromExpression(Expression? expression) {
  if (expression == null) {
    return null;
  }
  if (expression is InstanceCreationExpression) {
    return expression.constructorName.type.name2.lexeme;
  }
  if (expression is MethodInvocation) {
    for (final Expression argument
        in expression.argumentList.arguments.reversed) {
      final Expression unwrapped =
          argument is NamedExpression ? argument.expression : argument;
      final String? nested = _widgetTypeFromExpression(unwrapped);
      if (nested != null) {
        return nested;
      }
    }
  }
  return null;
}

String _pageClassToRouteId(String className) {
  if (className.endsWith('Page')) {
    return '${className.substring(0, className.length - 'Page'.length)}Route';
  }
  if (className.endsWith('Screen')) {
    return '${className.substring(0, className.length - 'Screen'.length)}Route';
  }
  if (className.endsWith('Route')) {
    return className;
  }
  return '${className}Route';
}

String? _guessPageFile(String projectRoot, String routeId) {
  String base = routeId;
  if (base.endsWith('Route')) {
    base = base.substring(0, base.length - 'Route'.length);
  }
  final List<String> candidates = <String>[
    '${base}Page',
    '${base}Screen',
    base,
  ];
  final Directory libDirectory = Directory(p.join(projectRoot, 'lib'));
  if (!libDirectory.existsSync()) {
    return null;
  }
  for (final String candidate in candidates) {
    final RegExp classPattern = RegExp('class\\s+$candidate\\b');
    for (final FileSystemEntity entity
        in libDirectory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.path.endsWith('.gr.dart')) {
        continue;
      }
      if (classPattern.hasMatch(entity.readAsStringSync())) {
        return _relative(projectRoot, entity.path);
      }
    }
  }
  return null;
}

class _DartUnit {
  const _DartUnit({required this.filePath, required this.unit});

  final String filePath;
  final CompilationUnit unit;
}

class _RouteCall {
  const _RouteCall({
    required this.name,
    required this.argumentList,
  });

  final String name;
  final ArgumentList argumentList;
}

List<_DartUnit> _loadDartUnits(String projectRoot) {
  final Directory libDirectory = Directory(p.join(projectRoot, 'lib'));
  if (!libDirectory.existsSync()) {
    return <_DartUnit>[];
  }
  final List<_DartUnit> units = <_DartUnit>[];
  for (final FileSystemEntity entity
      in libDirectory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (entity.path.endsWith('.gr.dart') || entity.path.endsWith('.g.dart')) {
      continue;
    }
    final ParseStringResult parseResult = parseString(
      content: entity.readAsStringSync(),
      path: entity.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    units.add(_DartUnit(filePath: entity.path, unit: parseResult.unit));
  }
  return units;
}

Annotation? _findAnnotation(
  ClassDeclaration declaration,
  Set<String> names,
) {
  for (final Annotation annotation in declaration.metadata) {
    final Identifier name = annotation.name;
    final String simple = name is PrefixedIdentifier
        ? name.identifier.name
        : name.name;
    if (names.contains(simple)) {
      return annotation;
    }
  }
  return null;
}

_RouteCall? _asRouteCall(Expression expression) {
  if (expression is InstanceCreationExpression) {
    return _RouteCall(
      name: expression.constructorName.type.name2.lexeme,
      argumentList: expression.argumentList,
    );
  }
  if (expression is MethodInvocation) {
    return _RouteCall(
      name: expression.methodName.name,
      argumentList: expression.argumentList,
    );
  }
  return null;
}

Expression? _namedArg(ArgumentList argumentList, String name) {
  for (final Expression argument in argumentList.arguments) {
    if (argument is NamedExpression && argument.name.label.name == name) {
      return argument.expression;
    }
  }
  return null;
}

String? _stringNamedArg(
  ArgumentList argumentList,
  String name, {
  ConstStringTable? constStrings,
  String? className,
  ClassDeclaration? ownerClass,
}) {
  final Expression? expression = _namedArg(argumentList, name);
  if (expression == null) {
    return null;
  }
  if (expression is SimpleStringLiteral) {
    return expression.value;
  }
  if (expression is AdjacentStrings) {
    return expression.stringValue;
  }
  // Paths are commonly a `static const routeName` rather than a literal.
  final String? resolved =
      constStrings?.resolveExpressionInClass(expression, className);
  if (resolved != null) {
    return resolved;
  }
  if (ownerClass != null && expression is SimpleIdentifier) {
    return _staticStringField(ownerClass, expression.name);
  }
  return null;
}

bool? _boolNamedArg(ArgumentList argumentList, String name) {
  final Expression? expression = _namedArg(argumentList, name);
  if (expression is BooleanLiteral) {
    return expression.value;
  }
  return null;
}

String _joinPaths(String parent, String child) {
  if (child.startsWith('/')) {
    return child == '/' ? '/' : child;
  }
  if (parent.isEmpty || parent == '/') {
    return '/$child';
  }
  final String normalizedParent =
      parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent;
  return '$normalizedParent/$child';
}

List<String> _paramsFromPath(String urlPath) {
  return urlPath
      .split('/')
      .where((String segment) => segment.startsWith(':'))
      .map((String segment) => segment.substring(1))
      .toList();
}

String _slugFromPath(String urlPath) {
  if (urlPath == '/' || urlPath.isEmpty) {
    return 'index';
  }
  return urlPath
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(':', '')
      .replaceAll('/', '_');
}

String _relative(String projectRoot, String filePath) {
  return p.relative(filePath, from: projectRoot).replaceAll(r'\', '/');
}
