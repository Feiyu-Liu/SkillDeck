import 'dart:convert';

import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:skills_workspace/src/infrastructure/source/well_known_index.dart';
import 'package:test/test.dart';

void main() {
  final indexUri = Uri.parse(
    'https://example.com/.well-known/agent-skills/index.json',
  );

  test('parses v2 without fetching or extracting artifacts', () {
    final result = parseWellKnownIndex(
      utf8.encode('''
{
  "\$schema": "$wellKnownDiscoverySchemaV2",
  "skills": [{
    "name": "example-skill",
    "description": "Description",
    "type": "skill-md",
    "url": "./example/SKILL.md",
    "digest": "sha256:${'a' * 64}"
  }]
}
'''),
      indexUri: indexUri,
      wellKnownPath: '.well-known/agent-skills',
    );

    final entry = result.valueOrNull!.entries.single;
    expect(entry.type, WellKnownArtifactType.skillMarkdown);
    expect(
      entry.artifactUri,
      Uri.parse(
        'https://example.com/.well-known/agent-skills/example/SKILL.md',
      ),
    );
  });

  test('rejects traversal in legacy declared files', () {
    final result = parseWellKnownIndex(
      utf8.encode('''
{"skills":[{"name":"example","description":"Description","files":["SKILL.md","../secret"]}]}
'''),
      indexUri: indexUri,
      wellKnownPath: '.well-known/agent-skills',
    );

    expect(result.failureOrNull?.code, SourceFailureCode.invalidSource);
    expect(result.failureOrNull?.context['reason'], 'unsafeDeclaredFilePath');
  });

  test('rejects duplicate names with portable case differences', () {
    final result = parseWellKnownIndex(
      utf8.encode('''
{"skills":[
  {"name":"example","description":"One","files":["SKILL.md"]},
  {"name":"EXAMPLE","description":"Two","files":["SKILL.md"]}
]}
'''),
      indexUri: indexUri,
      wellKnownPath: '.well-known/agent-skills',
    );

    expect(result.failureOrNull?.code, SourceFailureCode.invalidSource);
  });
}
