import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'source_models.dart';

final RegExp _frontmatterPattern = RegExp(
  r'^\uFEFF?(?:[ \t]*\r?\n)*---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)',
);

/// Parses only the leading YAML frontmatter needed to identify a Skill.
///
/// Standard YAML is preferred; a narrow compatibility pass handles common
/// unquoted colons in plain descriptions. Missing required fields and
/// ambiguous metadata remain invalid without leaking parser diagnostics.
SkillFrontmatter? parseSkillFrontmatter(String raw) {
  return inspectSkillFrontmatter(raw).frontmatter;
}

({SkillFrontmatter? frontmatter, String? reason}) inspectSkillFrontmatter(
  String raw,
) {
  final match = _frontmatterPattern.firstMatch(raw);
  if (match == null) {
    return (frontmatter: null, reason: 'invalidFrontmatter');
  }
  final body = match.group(1) ?? '';
  final values = _parseValues(body);
  if (values == null) {
    return (frontmatter: null, reason: 'invalidFrontmatter');
  }
  final name = values['name'];
  final description = values['description'];
  if (name is! String || name.trim().isEmpty) {
    return (frontmatter: null, reason: 'missingName');
  }
  if (description is! String || description.trim().isEmpty) {
    return (frontmatter: null, reason: 'missingDescription');
  }
  return (
    frontmatter: SkillFrontmatter(
      declaredName: name,
      description: description,
      values: values,
    ),
    reason: null,
  );
}

Map<String, Object?>? _parseValues(String body) {
  final strict = _tryParseValues(body);
  if (strict != null) return strict;
  final repaired = _repairPlainScalarColons(body);
  if (repaired == body) return null;
  return _tryParseValues(repaired);
}

Map<String, Object?>? _tryParseValues(String body) {
  try {
    return _plainStringMap(loadYaml(body));
  } on YamlException {
    return null;
  } on FormatException {
    return null;
  }
}

String _repairPlainScalarColons(String body) {
  final lines = body.split('\n');
  final repaired = <String>[];
  final fieldPattern = RegExp(r'^(description\s*:\s+)(.*)$');
  for (final line in lines) {
    final match = fieldPattern.firstMatch(line);
    if (match == null) {
      repaired.add(line);
      continue;
    }
    final value = match.group(2)!;
    final trimmed = value.trimRight();
    final first = trimmed.isEmpty ? '' : trimmed[0];
    final isPlainScalar =
        first != "'" && first != '"' && first != '|' && first != '>';
    if (isPlainScalar && RegExp(r':\s').hasMatch(trimmed)) {
      repaired.add('${match.group(1)}${jsonEncode(trimmed)}');
    } else {
      repaired.add(line);
    }
  }
  return repaired.join('\n');
}

Map<String, Object?>? _plainStringMap(Object? value) {
  if (value is! YamlMap && value is! Map<Object?, Object?>) {
    return null;
  }
  final entries = value is YamlMap
      ? value.entries
      : (value as Map<Object?, Object?>).entries;
  final result = <String, Object?>{};
  for (final entry in entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = _plainYaml(entry.value);
  }
  return result;
}

Object? _plainYaml(Object? value) {
  if (value is YamlMap) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        return null;
      }
      result[key] = _plainYaml(entry.value);
    }
    return result;
  }
  if (value is YamlList) {
    return value.nodes.map((node) => _plainYaml(node.value)).toList();
  }
  return value;
}
