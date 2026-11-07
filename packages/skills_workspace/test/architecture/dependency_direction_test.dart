import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _packageName = 'skills_workspace';
const _layers = <String>{
  'api',
  'application',
  'domain',
  'infrastructure',
  'platform',
  'native',
  'nativeBindings',
};
const _allowedDependencies = <String, Set<String>>{
  'domain': {'domain'},
  'application': {'application', 'domain'},
  'api': {'api', 'application', 'domain'},
  'infrastructure': {'infrastructure', 'application', 'domain'},
  'platform': {'platform', 'application', 'domain', 'nativeBindings'},
  'native': {'native', 'application', 'domain', 'nativeBindings'},
  'nativeBindings': {'nativeBindings'},
};
const _privateImplementationLayers = {
  'infrastructure',
  'platform',
  'native',
  'nativeBindings',
};

void main() {
  final packageRoot = Directory.current.absolute;
  final libDirectory = Directory(path.join(packageRoot.path, 'lib'));

  test('production imports do not depend on Flutter or the app', () {
    final violations = <String>[];

    for (final file in _dartFiles(libDirectory)) {
      for (final directive in _directives(file)) {
        for (final uri in directive.uris) {
          if (_isFlutterOrAppUri(uri)) {
            violations.add('${_relative(packageRoot, file)} imports $uri');
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('internal imports follow the planned dependency direction', () {
    final violations = <String>[];

    for (final file in _dartFiles(
      Directory(path.join(libDirectory.path, 'src')),
    )) {
      final sourceLayer = _layerFor(packageRoot, file);
      if (sourceLayer == null) {
        continue;
      }

      for (final directive in _directives(file)) {
        for (final uri in directive.uris) {
          final target = _resolvePackageFile(packageRoot, file, uri);
          if (target == null) {
            if (sourceLayer == 'domain' && !uri.startsWith('dart:')) {
              violations.add(
                '${_relative(packageRoot, file)} depends on external $uri',
              );
            }
            continue;
          }

          final targetLayer = _layerFor(packageRoot, target);
          if (targetLayer != null &&
              !_allowedDependencies[sourceLayer]!.contains(targetLayer)) {
            violations.add(
              '${_relative(packageRoot, file)} ($sourceLayer) depends on '
              '${_relative(packageRoot, target)} ($targetLayer)',
            );
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the public barrel cannot expose private implementation layers', () {
    final barrel = File(path.join(libDirectory.path, 'skills_workspace.dart'));
    final violations = <String>[];
    final visited = <String>{};

    void visitExports(File file) {
      final canonicalPath = path.normalize(file.absolute.path);
      if (!visited.add(canonicalPath)) {
        return;
      }

      for (final directive in _directives(
        file,
      ).where((item) => item.isExport)) {
        for (final uri in directive.uris) {
          final target = _resolvePackageFile(packageRoot, file, uri);
          if (target == null) {
            continue;
          }

          final layer = _layerFor(packageRoot, target);
          if (_privateImplementationLayers.contains(layer)) {
            violations.add(
              '${_relative(packageRoot, file)} exports '
              '${_relative(packageRoot, target)} ($layer)',
            );
          }
          if (target.existsSync()) {
            visitExports(target);
          }
        }
      }
    }

    visitExports(barrel);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) {
    return;
  }
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

Iterable<_Directive> _directives(File file) sync* {
  final source = file.readAsStringSync();
  final directives = RegExp(r'\b(import|export)\s+([^;]+);', multiLine: true);
  final uriLiterals = RegExp(r'''['"]([^'"]+)['"]''');

  for (final match in directives.allMatches(source)) {
    final uris = uriLiterals
        .allMatches(match.group(2)!)
        .map((uriMatch) => uriMatch.group(1)!)
        .toList(growable: false);
    yield _Directive(isExport: match.group(1) == 'export', uris: uris);
  }
}

File? _resolvePackageFile(Directory packageRoot, File source, String uri) {
  if (uri.startsWith('package:$_packageName/')) {
    final packagePath = uri.substring('package:$_packageName/'.length);
    return File(
      path.normalize(path.join(packageRoot.path, 'lib', packagePath)),
    );
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) {
    return null;
  }
  return File(path.normalize(path.join(source.parent.path, uri)));
}

String? _layerFor(Directory packageRoot, File file) {
  final relative = path.split(_relative(packageRoot, file));
  if (relative.length < 4 || relative[0] != 'lib' || relative[1] != 'src') {
    return null;
  }
  if (relative[2] == 'native' && relative[3] == 'generated') {
    return 'nativeBindings';
  }
  return _layers.contains(relative[2]) ? relative[2] : null;
}

bool _isFlutterOrAppUri(String uri) {
  return uri == 'dart:ui' ||
      uri == 'package:flutter' ||
      uri.startsWith('package:flutter/') ||
      uri.startsWith('package:flutter_') ||
      uri == 'package:skills_manager' ||
      uri.startsWith('package:skills_manager/');
}

String _relative(Directory packageRoot, File file) =>
    path.relative(file.absolute.path, from: packageRoot.path);

final class _Directive {
  const _Directive({required this.isExport, required this.uris});

  final bool isExport;
  final List<String> uris;
}
