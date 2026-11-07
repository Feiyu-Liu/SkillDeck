import 'package:skills_workspace/src/infrastructure/source/frontmatter_parser.dart';
import 'package:test/test.dart';

void main() {
  for (final prefix in ['\uFEFF', '\n', '\uFEFF\r\n\n']) {
    test('accepts BOM and blank prefix ${prefix.codeUnits}', () {
      expect(
        parseSkillFrontmatter(
          '$prefix---\nname: demo\ndescription: demo\n---\n',
        )?.declaredName,
        'demo',
      );
    });
  }

  test('parses required fields and freezes nested metadata', () {
    final parsed = parseSkillFrontmatter('''
---
name: example-skill
description: Example description
metadata:
  internal: true
---
# Body
''');

    expect(parsed?.declaredName, 'example-skill');
    expect(parsed?.description, 'Example description');
    expect(parsed?.isInternal, isTrue);
    expect(() => parsed!.values['changed'] = true, throwsUnsupportedError);
  });

  test('rejects missing frontmatter and non-string keys', () {
    expect(parseSkillFrontmatter('# Body'), isNull);
    expect(
      parseSkillFrontmatter('''
---
1: invalid
name: example
description: description
---
'''),
      isNull,
    );
  });
}
