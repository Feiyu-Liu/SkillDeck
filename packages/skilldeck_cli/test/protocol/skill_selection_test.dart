import 'dart:convert';

import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('selection round trips every field through JSON and a request', () {
    final selection = SkillSelection(
      refs: ['opaque-id', 'slot'],
      tags: ['Testing', '技能'],
      untagged: true,
      favorite: true,
      sourcePrefix: 'https://example.test/',
      activeFor: 'codex',
      projectPath: '/projects/demo',
      hasUpdate: true,
      all: true,
    );
    final request = CommandRequest(
      command: 'list',
      arguments: {'selection': selection.toJson()},
    );
    final decoded = WireMessage.fromJson(
      jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>,
    ) as CommandRequest;
    expect(
      SkillSelection.fromJson(
        decoded.arguments['selection'] as Map<String, Object?>,
      ).toJson(),
      selection.toJson(),
    );
    expect(selection.hasFilters, isTrue);
    expect(selection.isEmpty, isFalse);
  });
  test('defaults and lists are immutable and defensively copied', () {
    final refs = ['one'];
    final tags = ['tag'];
    final selection = SkillSelection(refs: refs, tags: tags);
    refs.clear();
    tags.clear();
    expect(selection.refs, ['one']);
    expect(selection.tags, ['tag']);
    expect(() => selection.refs.add('two'), throwsUnsupportedError);
    expect(() => selection.tags.clear(), throwsUnsupportedError);
    expect(SkillSelection.fromJson({}).isEmpty, isTrue);
    expect(
      SkillSelection.fromJson(SkillSelection().toJson()).toJson(),
      SkillSelection().toJson(),
    );
  });
  test('malformed fields are rejected', () {
    for (final value in <Map<String, Object?>>[
      {
        'refs': [1],
      },
      {'tags': 'tag'},
      {'favorite': 'yes'},
      {'projectPath': 1},
      {'hasUpdate': 1},
    ]) {
      expect(() => SkillSelection.fromJson(value), throwsA(anything));
    }
  });
}
