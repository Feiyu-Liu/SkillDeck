import 'package:flutter_md/flutter_md.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation/src/markdown_source_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('shared Markdown source adapter', () {
    test('uses source parser IDs and preserves exact CRLF gaps', () {
      final document = TranslationMarkdownSource.parse(
        '# Title\r\n\r\nParagraph\r\n',
      );

      expect(document.blocks.map((block) => block.id.value), [
        'b:0:7',
        'b:11:20',
      ]);
      expect(
        document.applyReplacements(
          translatedBlocks: {const MarkdownBlockId(11, 20): '段落'},
          translatedDescription: null,
        ),
        '# Title\r\n\r\n段落\r\n',
      );
    });

    test('keeps lists and tables whole while code remains local', () {
      final document = TranslationMarkdownSource.parse(
        '- one\n- two\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```dart\nx();\n```',
      );

      expect(document.blocks.map((block) => block.rootType), ['list', 'table']);
      expect(document.blocks.first.source, '- one\n- two');
      expect(document.blocks.last.source, '| A | B |\n|---|---|\n| 1 | 2 |');
    });

    test('uses display-body IDs unchanged around protected frontmatter', () {
      final document = TranslationMarkdownSource.parse(
        '---\nname: demo\ndescription: Source.\n---\n# Body',
      );

      expect(document.descriptionSource, 'Source.');
      expect(document.blocks.single.source, '# Body');
      expect(document.blocks.single.id.value, 'b:0:6');
      expect(
        document.blocks.single.id,
        const MarkdownSourceParser().parse('# Body').blocks.single.id,
      );
    });

    test('shares tolerant SKILL.md frontmatter projection with the renderer', () {
      const source =
          '\uFEFF---  \r\nname: demo\r\ndescription: Source.\r\n---\t\r\n\r\n# Body\r\n';

      final display = parseTranslationDisplayDocument(
        documentIdentifier: 'SKILL.md',
        content: source,
      );

      expect(display.source, '\r\n# Body\r\n');
      expect(display.blocks.last.id, const MarkdownBlockId(2, 8));
    });

    test('uses full-document renderer IDs for non-SKILL frontmatter', () {
      const source = '---\r\ndescription: Guide\r\n---\r\n# Body\r\n\r\nText';
      final display = parseTranslationDisplayDocument(
        documentIdentifier: 'references/guide.md',
        content: source,
      );
      final document = TranslationMarkdownSource.parse(
        source,
        documentIdentifier: 'references/guide.md',
      );

      expect(display.source, source);
      expect(document.blocks.map((block) => block.id), [
        display.blocks[3].id,
        display.blocks[5].id,
      ]);
      expect(
        document.applyReplacements(
          translatedBlocks: {document.blocks.first.id: '# 正文'},
          translatedDescription: '指南',
        ),
        '---\r\ndescription: "指南"\r\n---\r\n# 正文\r\n\r\nText',
      );
    });

    test('keeps malformed or unterminated frontmatter local', () {
      final malformed = TranslationMarkdownSource.parse(
        '---\ndescription: [broken\n---\n# Body',
      );
      final unterminated = TranslationMarkdownSource.parse(
        '---\ndescription: private\n# Body',
      );

      expect(malformed.descriptionSource, isNull);
      expect(malformed.blocks.single.source, '# Body');
      expect(unterminated.blocks, isEmpty);
      expect(unterminated.descriptionSource, isNull);
      expect(
        parseTranslationDisplayDocument(
          documentIdentifier: 'SKILL.md',
          content: '---\ndescription: private\n# Body',
        ).source,
        '---\ndescription: private\n# Body',
      );
    });
  });
}
