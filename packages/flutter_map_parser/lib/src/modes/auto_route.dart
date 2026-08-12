import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_map_parser/src/const_strings.dart';
import 'package:flutter_map_parser/src/model.dart';
import 'package:path/path.dart' as p;

/// Constructor names that build an `AutoRoute` (or one of its subclasses).
///
/// auto_route ships several `AutoRoute` subclasses and real apps use them far
/// more often than the base class, so the route table has to accept the whole
/// family rather than a single name.
const Set<String> _routeConstructorNames = <String>{
  'AutoRoute',
  'AdaptiveRoute',
  'CustomRoute',
  'MaterialRoute',
  'CupertinoRoute',
};

/// Maximum number of `X.route` -> `Y.route` hops followed for one entry.
const int _maxReferenceHops = 8;

/// Result of parsing `@AutoRouterConfig` route tables.
class AutoRouteParseResult {
  const AutoRouteParseResult({
    required this.routes,
    required this.layouts,
    required this.routerFile,
  });

  final List<RouteNode> routes;
  final List<LayoutNode> layouts;
  final String? routerFile;
}

/// Parses auto_route `@AutoRouterConfig` routers under [projectRoot]/lib.
AutoRouteParseResult parseAutoRouteProject(String projectRoot) {
  final List<_DartUnit> units = _loadDartUnits(projectRoot);
  final _ResolveContext context = _ResolveContext.build(
    projectRoot: projectRoot,
    units: units,
  );
  final String? replaceInRouteName = _findReplaceInRouteName(units);
  final Map<String, _RoutePageBinding> routePageFiles = _collectRoutePageFiles(
    projectRoot: projectRoot,
    units: units,
    replaceInRouteName: replaceInRouteName,
  );
  final List<RouteNode> routes = <RouteNode>[];
  final List<LayoutNode> layouts = <LayoutNode>[];
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
        context: context,
        owner: context.classes[declaration.name.lexeme],
        activeRefs: const <String>{},
      );
    }
  }
  return AutoRouteParseResult(
    routes: routes,
    layouts: layouts,
    routerFile: routerFile,
  );
}

void _walkAutoRoutes({
  required Expression expression,
  required String parentPath,
  required String projectRoot,
  required Map<String, _RoutePageBinding> routePageFiles,
  required List<RouteNode> routes,
  required List<LayoutNode> layouts,
  required Set<String> seenIds,
  required String routerFile,
  required _ResolveContext context,
  required _ClassEntry? owner,
  required Set<String> activeRefs,
}) {
  final ListLiteral? list = expression is ListLiteral ? expression : null;
  if (list == null) {
    return;
  }
  for (final CollectionElement element in list.elements) {
    if (element is! Expression) {
      continue;
    }
    _RouteCall? call = _asRouteCall(element);
    if (call != null && call.name == 'RedirectRoute') {
      continue;
    }
    _ClassEntry? elementOwner = owner;
    Set<String> childRefs = activeRefs;
    if (call == null || !_routeConstructorNames.contains(call.name)) {
      // Reku-style indirection: the route table holds `X.route` or
      // `X.route(...)` and the real constructor lives on class `X`.
      final _ResolvedReference? resolved = context.resolveRouteReference(
        expression: element,
        blocked: activeRefs,
      );
      if (resolved == null) {
        continue;
      }
      call = _asRouteCall(resolved.expression);
      if (call == null || !_routeConstructorNames.contains(call.name)) {
        continue;
      }
      elementOwner = resolved.owner;
      childRefs = <String>{...activeRefs, ...resolved.chain};
    }
    final String? pageType = _pageTypeName(call.argumentList);
    final String? rawPath = _pathNamedArg(
      argumentList: call.argumentList,
      owner: elementOwner,
      context: context,
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
    if (hasChildren) {
      layouts.add(
        LayoutNode(
          file: routerFile,
          dir: absolutePath == '/' ? '' : absolutePath,
          navigator: 'stack',
        ),
      );
    }
    if (seenIds.add(id)) {
      final _RoutePageBinding? binding = routePageFiles[id];
      final bool ownerIsPageLike = elementOwner != null &&
          !_isRouterLikePath(elementOwner.file);
      final String file = binding?.file ??
          (ownerIsPageLike ? elementOwner.file : null) ??
          _guessPageFile(context, id) ??
          routerFile;
      routes.add(
        RouteNode(
          id: id,
          urlPath: absolutePath.isEmpty ? '/' : absolutePath,
          file: file,
          slug: _slugFromPath(absolutePath.isEmpty ? '/' : absolutePath),
          params: _paramsFromPath(absolutePath),
          navigator: hasChildren
              ? 'stack'
              : (layouts.isEmpty ? 'stack' : layouts.last.navigator),
          layoutDir: layouts.isEmpty ? '' : layouts.last.dir,
          presentation: _presentation(call.argumentList),
          widgetName: binding?.widgetName ??
              (ownerIsPageLike ? elementOwner.className : null),
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
        context: context,
        owner: elementOwner,
        activeRefs: childRefs,
      );
    }
  }
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

/// A class declaration plus the file and constant scope it was declared in.
class _ClassEntry {
  const _ClassEntry({
    required this.className,
    required this.declaration,
    required this.file,
    required this.consts,
  });

  final String className;
  final ClassDeclaration declaration;

  /// Path relative to the project root, e.g. `lib/screens/home_main.dart`.
  final String file;

  /// Constants declared in the same compilation unit as [declaration].
  final ConstStringTable consts;
}

/// One resolved `X.route` reference.
class _ResolvedReference {
  const _ResolvedReference({
    required this.expression,
    required this.owner,
    required this.chain,
  });

  /// The route constructor expression the reference pointed at.
  final Expression expression;

  /// The class that declared [expression].
  final _ClassEntry owner;

  /// `Class.member` keys followed to get here, used as a cycle guard.
  final Set<String> chain;
}

class _MemberRef {
  const _MemberRef({required this.className, required this.memberName});

  final String className;
  final String memberName;

  String get key => '$className.$memberName';
}

/// Index of every class in the project, used to follow route references.
class _ResolveContext {
  const _ResolveContext({
    required this.classes,
    required this.globalConsts,
  });

  final Map<String, _ClassEntry> classes;

  /// `Class.member` -> value for every resolvable string constant.
  final Map<String, String> globalConsts;

  static _ResolveContext build({
    required String projectRoot,
    required List<_DartUnit> units,
  }) {
    final Map<String, _ClassEntry> classes = <String, _ClassEntry>{};
    final Map<String, String> globalConsts = <String, String>{};
    for (final _DartUnit unit in units) {
      final ConstStringTable table = ConstStringTable.fromUnit(unit.unit);
      final String file = _relative(projectRoot, unit.filePath);
      table.values.forEach((String key, String value) {
        if (key.contains('.')) {
          globalConsts.putIfAbsent(key, () => value);
        }
      });
      for (final ClassDeclaration declaration
          in unit.unit.declarations.whereType<ClassDeclaration>()) {
        classes.putIfAbsent(
          declaration.name.lexeme,
          () => _ClassEntry(
            className: declaration.name.lexeme,
            declaration: declaration,
            file: file,
            consts: table,
          ),
        );
      }
    }
    return _ResolveContext(classes: classes, globalConsts: globalConsts);
  }

  /// Follows `X.route` / `X.route(...)` until it lands on a route constructor.
  ///
  /// Returns null when the reference cannot be resolved, or when following it
  /// would revisit a member already on the current chain.
  _ResolvedReference? resolveRouteReference({
    required Expression expression,
    required Set<String> blocked,
  }) {
    final Set<String> chain = <String>{};
    Expression current = expression;
    for (int hop = 0; hop < _maxReferenceHops; hop++) {
      final _MemberRef? ref = _memberRefOf(current);
      if (ref == null) {
        return null;
      }
      if (blocked.contains(ref.key) || !chain.add(ref.key)) {
        return null;
      }
      final _ClassEntry? entry = classes[ref.className];
      if (entry == null) {
        return null;
      }
      final Expression? value =
          _memberExpression(entry.declaration, ref.memberName);
      if (value == null) {
        return null;
      }
      final _RouteCall? call = _asRouteCall(value);
      if (call != null && _routeConstructorNames.contains(call.name)) {
        return _ResolvedReference(
          expression: value,
          owner: entry,
          chain: chain,
        );
      }
      current = value;
    }
    return null;
  }
}

_MemberRef? _memberRefOf(Expression expression) {
  if (expression is PrefixedIdentifier) {
    return _MemberRef(
      className: expression.prefix.name,
      memberName: expression.identifier.name,
    );
  }
  if (expression is PropertyAccess) {
    final Expression? target = expression.target;
    if (target is SimpleIdentifier) {
      return _MemberRef(
        className: target.name,
        memberName: expression.propertyName.name,
      );
    }
  }
  if (expression is MethodInvocation) {
    final Expression? target = expression.target;
    if (target is SimpleIdentifier) {
      return _MemberRef(
        className: target.name,
        memberName: expression.methodName.name,
      );
    }
  }
  return null;
}

/// Returns the expression behind a `route` member in any of the three forms
/// Reku uses: expression-bodied method, getter, or initialised field.
Expression? _memberExpression(ClassDeclaration declaration, String memberName) {
  for (final ClassMember member in declaration.members) {
    if (member is MethodDeclaration && member.name.lexeme == memberName) {
      return _getterExpression(member);
    }
    if (member is FieldDeclaration) {
      for (final VariableDeclaration variable in member.fields.variables) {
        if (variable.name.lexeme == memberName) {
          return variable.initializer;
        }
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

/// Reads `replaceInRouteName` off the `@AutoRouterConfig` annotation.
///
/// auto_route derives generated route class names from it, so the parser has
/// to apply the same rule to bind `XxxRoute` ids back to their source files.
String? _findReplaceInRouteName(List<_DartUnit> units) {
  for (final _DartUnit unit in units) {
    for (final ClassDeclaration declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      final Annotation? config = _findAnnotation(
        declaration,
        <String>{'AutoRouterConfig'},
      );
      final ArgumentList? arguments = config?.arguments;
      if (arguments == null) {
        continue;
      }
      final String? value =
          _stringNamedArg(arguments, 'replaceInRouteName');
      if (value != null) {
        return value;
      }
    }
  }
  return null;
}

String _applyReplaceInRouteName(String className, String rule) {
  final List<String> parts = rule.split(',');
  if (parts.length != 2) {
    return '${className}Route';
  }
  final String replaced = className.replaceAll(RegExp(parts[0]), parts[1]);
  if (replaced.isEmpty) {
    return '${className}Route';
  }
  return '${replaced[0].toUpperCase()}${replaced.substring(1)}';
}

Map<String, _RoutePageBinding> _collectRoutePageFiles({
  required String projectRoot,
  required List<_DartUnit> units,
  String? replaceInRouteName,
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
      final ArgumentList? routePageArguments = routePage.arguments;
      final String? explicitName = routePageArguments == null
          ? null
          : _stringNamedArg(routePageArguments, 'name');
      final Set<String> routeIds = <String>{
        _pageClassToRouteId(className),
        if (explicitName != null) explicitName,
        if (replaceInRouteName != null)
          _applyReplaceInRouteName(className, replaceInRouteName),
      };
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
      for (final String routeId in routeIds) {
        _mergeRoutePageBinding(
          bindings: bindings,
          routeId: routeId,
          binding: _RoutePageBinding(
            file: resolvedFile,
            widgetName: widgetName,
          ),
        );
      }
    }
  }
  return bindings;
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

String? _guessPageFile(_ResolveContext context, String routeId) {
  String base = routeId;
  if (base.endsWith('Route')) {
    base = base.substring(0, base.length - 'Route'.length);
  }
  final List<String> candidates = <String>[
    '${base}Page',
    '${base}Screen',
    base,
  ];
  for (final String candidate in candidates) {
    final _ClassEntry? entry = context.classes[candidate];
    if (entry != null) {
      return entry.file;
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

String? _stringNamedArg(ArgumentList argumentList, String name) {
  final Expression? expression = _namedArg(argumentList, name);
  if (expression is SimpleStringLiteral) {
    return expression.value;
  }
  if (expression is AdjacentStrings) {
    return expression.stringValue;
  }
  return null;
}

/// Resolves `path:` which is a literal upstream but a `static const routeName`
/// reference in every Reku screen.
String? _pathNamedArg({
  required ArgumentList argumentList,
  required _ClassEntry? owner,
  required _ResolveContext context,
}) {
  final Expression? expression = _namedArg(argumentList, 'path');
  if (expression == null) {
    return null;
  }
  if (expression is SimpleStringLiteral) {
    return expression.value;
  }
  if (expression is AdjacentStrings) {
    return expression.stringValue;
  }
  if (owner != null) {
    if (expression is SimpleIdentifier) {
      final String? scoped =
          owner.consts.values['${owner.className}.${expression.name}'];
      if (scoped != null) {
        return scoped;
      }
    }
    final String? resolved = owner.consts.resolveExpression(expression);
    if (resolved != null) {
      return resolved;
    }
    if (expression is SimpleIdentifier) {
      final String? field = _stringFieldOf(owner, expression.name);
      if (field != null) {
        return field;
      }
    }
  }
  final _MemberRef? ref = _memberRefOf(expression);
  if (ref != null) {
    final String? global = context.globalConsts[ref.key];
    if (global != null) {
      return global;
    }
    final _ClassEntry? entry = context.classes[ref.className];
    if (entry != null) {
      return _stringFieldOf(entry, ref.memberName);
    }
  }
  return null;
}

/// Reads a string-literal field off a class regardless of `const` / `final`.
///
/// [ConstStringTable] only tracks compile-time constants, but a handful of Reku
/// screens declare `static String routeName = '...'`, which is still a usable
/// static path.
String? _stringFieldOf(_ClassEntry entry, String fieldName) {
  for (final ClassMember member in entry.declaration.members) {
    if (member is! FieldDeclaration) {
      continue;
    }
    for (final VariableDeclaration variable in member.fields.variables) {
      if (variable.name.lexeme != fieldName) {
        continue;
      }
      final Expression? initializer = variable.initializer;
      if (initializer is SimpleStringLiteral) {
        return initializer.value;
      }
      if (initializer is AdjacentStrings) {
        return initializer.stringValue;
      }
      return null;
    }
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
