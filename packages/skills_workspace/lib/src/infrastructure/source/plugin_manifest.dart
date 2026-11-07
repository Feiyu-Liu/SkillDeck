import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;

import 'source_result.dart';

const int _maximumManifestBytes = 1024 * 1024;

final class PluginManifestIndex {
  PluginManifestIndex({
    required List<String> searchDirectories,
    required Map<String, String> groupings,
  }) : searchDirectories = List<String>.unmodifiable(searchDirectories),
       groupings = Map<String, String>.unmodifiable(groupings);

  final List<String> searchDirectories;
  final Map<String, String> groupings;
}

Future<SourceResult<PluginManifestIndex>> readPluginManifestIndex(
  String basePath, {
  SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
}) async {
  if (cancellation.isCancelled) {
    return SourceFailure<PluginManifestIndex>(
      code: SourceFailureCode.cancelled,
    );
  }
  final normalizedBase = paths.normalize(paths.absolute(basePath));
  final manifestDirectory = paths.join(normalizedBase, '.claude-plugin');
  if (await FileSystemEntity.type(manifestDirectory, followLinks: false) ==
      FileSystemEntityType.link) {
    return SourceSuccess<PluginManifestIndex>(
      value: PluginManifestIndex(
        searchDirectories: const <String>[],
        groupings: const <String, String>{},
      ),
    );
  }

  final searchDirectories = <String>[];
  final groupings = <String, String>{};

  void addPlugin({
    required String pluginBase,
    required List<String>? skillPaths,
    required String? pluginName,
  }) {
    final normalizedPluginBase = paths.normalize(paths.absolute(pluginBase));
    if (!_isContained(normalizedBase, normalizedPluginBase)) {
      return;
    }
    if (skillPaths != null && skillPaths.isNotEmpty) {
      for (final skillPath in skillPaths) {
        if (!_isValidManifestPath(skillPath)) {
          continue;
        }
        final skillDirectory = paths.normalize(
          paths.join(normalizedPluginBase, skillPath),
        );
        // The declared Skill's parent is what discovery searches, so that is
        // the directory that must stay inside the Source. A Skill path of
        // `./` at the Source root would otherwise search the Source's parent.
        final searchDirectory = paths.dirname(skillDirectory);
        if (!_isContained(normalizedBase, searchDirectory)) {
          continue;
        }
        searchDirectories.add(searchDirectory);
        if (pluginName != null && pluginName.trim().isNotEmpty) {
          groupings[paths.normalize(paths.absolute(skillDirectory))] =
              pluginName;
        }
      }
    }
    searchDirectories.add(paths.join(normalizedPluginBase, 'skills'));
  }

  final marketplace = await _readJsonObject(
    paths.join(manifestDirectory, 'marketplace.json'),
  );
  if (cancellation.isCancelled) {
    return SourceFailure<PluginManifestIndex>(
      code: SourceFailureCode.cancelled,
    );
  }
  if (marketplace != null) {
    final metadata = _objectMap(marketplace['metadata']);
    final pluginRootValue = metadata?['pluginRoot'];
    final pluginRoot = pluginRootValue is String ? pluginRootValue : null;
    final validPluginRoot =
        pluginRootValue == null ||
        (pluginRoot != null && _isValidManifestPath(pluginRoot));
    final plugins = marketplace['plugins'];
    if (validPluginRoot && plugins is List<Object?>) {
      for (final value in plugins) {
        final plugin = _objectMap(value);
        if (plugin == null) {
          continue;
        }
        final sourceValue = plugin['source'];
        if (sourceValue != null && sourceValue is! String) {
          continue;
        }
        final source = sourceValue is String ? sourceValue : null;
        if (source != null && !_isValidManifestPath(source)) {
          continue;
        }
        addPlugin(
          pluginBase: paths.join(
            normalizedBase,
            pluginRoot ?? '',
            source ?? '',
          ),
          skillPaths: _stringList(plugin['skills']),
          pluginName: plugin['name'] is String
              ? plugin['name']! as String
              : null,
        );
      }
    }
  }

  final plugin = await _readJsonObject(
    paths.join(manifestDirectory, 'plugin.json'),
  );
  if (cancellation.isCancelled) {
    return SourceFailure<PluginManifestIndex>(
      code: SourceFailureCode.cancelled,
    );
  }
  if (plugin != null) {
    addPlugin(
      pluginBase: normalizedBase,
      skillPaths: _stringList(plugin['skills']),
      pluginName: plugin['name'] is String ? plugin['name']! as String : null,
    );
  }

  return SourceSuccess<PluginManifestIndex>(
    value: PluginManifestIndex(
      searchDirectories: _deduplicate(searchDirectories),
      groupings: groupings,
    ),
  );
}

Future<Map<String, Object?>?> _readJsonObject(String filePath) async {
  try {
    if (await FileSystemEntity.type(filePath, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final file = File(filePath);
    final stat = await file.stat();
    if (stat.size > _maximumManifestBytes) {
      return null;
    }
    final bytes = await file
        .openRead(0, _maximumManifestBytes + 1)
        .fold(<int>[], (buffer, chunk) => buffer..addAll(chunk));
    if (bytes.length > _maximumManifestBytes) {
      return null;
    }
    return _objectMap(jsonDecode(utf8.decode(bytes)));
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value;
  }
  return result;
}

List<String>? _stringList(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List<Object?> || value.any((element) => element is! String)) {
    return null;
  }
  return value.cast<String>();
}

/// Whether [value] is a manifest-relative path: `./` alone (the base itself)
/// or `./` followed by plain segments, with an optional trailing `/`.
///
/// Claude Code manifests commonly declare a plugin `source` of `./`; the
/// upstream `skills` CLI accepts it, so rejecting it would drop the whole
/// plugin entry. Traversal, backslashes, NUL, and empty or dot segments stay
/// rejected; callers still check containment of every resolved directory.
bool _isValidManifestPath(String value) {
  if (!value.startsWith('./') ||
      value.contains(r'\') ||
      value.contains('\x00')) {
    return false;
  }
  var rest = value.substring(2);
  if (rest.endsWith('/')) rest = rest.substring(0, rest.length - 1);
  if (rest.isEmpty) return value == './';
  return rest
      .split('/')
      .every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

bool _isContained(String base, String target) =>
    paths.equals(base, target) || paths.isWithin(base, target);

List<String> _deduplicate(List<String> values) {
  final seen = <String>{};
  return values.where(seen.add).toList(growable: false);
}
