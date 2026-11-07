import 'dart:convert';

import 'package:flutter_md/flutter_md.dart';
import 'package:yaml/yaml.dart';

const String frontmatterDescriptionWireId = 'frontmatter:description';

/// The exact SKILL.md description the translator can upload, if any.
String? readTranslatableSkillDescription(String content) {
  final frontmatter = _leadingFrontmatter(content);
  return frontmatter == null ? null : _descriptionField(frontmatter)?.value;
}

/// Parses the exact Markdown coordinate space used to display a Source
/// Document and to apply live Translation Draft replacements.
MarkdownSourceDocument parseTranslationDisplayDocument({
  required String documentIdentifier,
  required String content,
}) =>
    TranslationMarkdownSource.parse(
      content,
      documentIdentifier: documentIdentifier,
    ).displayDocument;

final class TranslationMarkdownBlock {
  const TranslationMarkdownBlock({
    required this.id,
    required this.source,
    required this.rootType,
  });

  final MarkdownBlockId id;
  final String source;
  final String rootType;
}

final class TranslationMarkdownSource {
  TranslationMarkdownSource._({
    required this.source,
    required this.displayDocument,
    required this.prefixEndOffset,
    required this.description,
    required this.blocks,
  });

  factory TranslationMarkdownSource.parse(
    String source, {
    String documentIdentifier = 'SKILL.md',
  }) {
    final parser = const MarkdownSourceParser();
    final frontmatter = _leadingFrontmatter(source);
    if (frontmatter == null) {
      if (_startsWithFrontmatterDelimiter(source)) {
        return TranslationMarkdownSource._(
          source: source,
          displayDocument: parser.parse(source),
          prefixEndOffset: 0,
          description: null,
          blocks: const <TranslationMarkdownBlock>[],
        );
      }
      return TranslationMarkdownSource._fromDisplayDocument(
        source: source,
        displayDocument: parser.parse(source),
        prefixEndOffset: 0,
      );
    }

    final hidesFrontmatter = documentIdentifier == 'SKILL.md';
    final displayDocument = parser.parse(
      hidesFrontmatter ? source.substring(frontmatter.endOffset) : source,
    );
    return TranslationMarkdownSource._fromDisplayDocument(
      source: source,
      displayDocument: displayDocument,
      prefixEndOffset: hidesFrontmatter ? frontmatter.endOffset : 0,
      firstBodyOffset: hidesFrontmatter ? 0 : frontmatter.endOffset,
      description: _descriptionField(frontmatter),
    );
  }

  factory TranslationMarkdownSource._fromDisplayDocument({
    required String source,
    required MarkdownSourceDocument displayDocument,
    required int prefixEndOffset,
    int firstBodyOffset = 0,
    _DescriptionField? description,
  }) {
    final blocks = <TranslationMarkdownBlock>[
      for (final block in displayDocument.blocks)
        if (block.start >= firstBodyOffset && _isTranslatable(block))
          TranslationMarkdownBlock(
            id: block.id,
            source: block.source,
            rootType: block.block.type,
          ),
    ];
    return TranslationMarkdownSource._(
      source: source,
      displayDocument: displayDocument,
      prefixEndOffset: prefixEndOffset,
      description: description,
      blocks: List<TranslationMarkdownBlock>.unmodifiable(blocks),
    );
  }

  final String source;
  final MarkdownSourceDocument displayDocument;
  final int prefixEndOffset;
  final _DescriptionField? description;
  final List<TranslationMarkdownBlock> blocks;

  String? get descriptionSource => description?.value;

  String applyReplacements({
    required Map<MarkdownBlockId, String> translatedBlocks,
    required String? translatedDescription,
  }) {
    final knownIds = blocks.map((block) => block.id).toSet();
    for (final replacement in translatedBlocks.entries) {
      if (!knownIds.contains(replacement.key)) {
        throw ArgumentError.value(
          replacement.key,
          'translatedBlocks',
          'Unknown Markdown block ID',
        );
      }
    }

    var translatedDisplay = displayDocument.applyReplacements(translatedBlocks);
    final description = this.description;
    if (translatedDescription != null) {
      if (description == null) {
        throw ArgumentError.value(
          translatedDescription,
          'translatedDescription',
          'The source document has no translatable frontmatter description',
        );
      }
    }

    if (prefixEndOffset == 0) {
      if (translatedDescription != null) {
        translatedDisplay = _replaceDescription(
          translatedDisplay,
          description!,
          translatedDescription,
        );
      }
      return translatedDisplay;
    }

    var prefix = source.substring(0, prefixEndOffset);
    if (translatedDescription != null) {
      prefix = _replaceDescription(prefix, description!, translatedDescription);
    }
    return '$prefix$translatedDisplay';
  }
}

String _replaceDescription(
  String document,
  _DescriptionField description,
  String translatedDescription,
) =>
    '${document.substring(0, description.startOffset)}'
    '"${_yamlDoubleQuotedContent(translatedDescription)}"'
    '${document.substring(description.endOffset)}';

bool _isTranslatable(MarkdownSourceBlock block) =>
    block.source.trim().isNotEmpty &&
    block.block.type != 'code' &&
    block.block.type != 'divider' &&
    block.block.type != 'spacer';

final class _LeadingFrontmatter {
  const _LeadingFrontmatter({
    required this.body,
    required this.bodyOffset,
    required this.endOffset,
  });

  final String body;
  final int bodyOffset;
  final int endOffset;
}

final class _DescriptionField {
  const _DescriptionField({
    required this.value,
    required this.startOffset,
    required this.endOffset,
  });

  final String value;
  final int startOffset;
  final int endOffset;
}

_LeadingFrontmatter? _leadingFrontmatter(String document) {
  final lines = _linesWithEndings(document).iterator;
  if (!lines.moveNext() || !_isOpeningDelimiter(lines.current)) {
    return null;
  }

  final bodyOffset = lines.current.length;
  var offset = bodyOffset;
  while (lines.moveNext()) {
    final line = lines.current;
    if (_isClosingDelimiter(line)) {
      return _LeadingFrontmatter(
        body: document.substring(bodyOffset, offset),
        bodyOffset: bodyOffset,
        endOffset: offset + line.length,
      );
    }
    offset += line.length;
  }
  return null;
}

bool _startsWithFrontmatterDelimiter(String document) {
  final lines = _linesWithEndings(document).iterator;
  return lines.moveNext() && _isOpeningDelimiter(lines.current);
}

bool _isOpeningDelimiter(String line) =>
    RegExp(r'^\uFEFF?---[ \t]*$').hasMatch(_withoutLineEnding(line));

bool _isClosingDelimiter(String line) =>
    RegExp(r'^---[ \t]*$').hasMatch(_withoutLineEnding(line));

_DescriptionField? _descriptionField(_LeadingFrontmatter frontmatter) {
  try {
    final root = loadYamlNode(frontmatter.body);
    if (root is! YamlMap) return null;
    final node = root.nodes['description'];
    if (node is! YamlScalar || node.value is! String) return null;
    final start = node.span.start.offset;
    final end = node.span.end.offset;
    if (start < 0 || end <= start || end > frontmatter.body.length) return null;
    final value = node.value as String;
    if (value.trim().isEmpty) return null;
    return _DescriptionField(
      value: value,
      startOffset: frontmatter.bodyOffset + start,
      endOffset: frontmatter.bodyOffset + end,
    );
  } on YamlException {
    return null;
  }
}

String _yamlDoubleQuotedContent(String value) {
  final encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

Iterable<String> _linesWithEndings(String source) sync* {
  var start = 0;
  while (start < source.length) {
    var end = start;
    while (end < source.length &&
        source.codeUnitAt(end) != 0x0A &&
        source.codeUnitAt(end) != 0x0D) {
      end += 1;
    }
    if (end == source.length) {
      yield source.substring(start);
      return;
    }
    if (source.codeUnitAt(end) == 0x0D &&
        end + 1 < source.length &&
        source.codeUnitAt(end + 1) == 0x0A) {
      end += 1;
    }
    yield source.substring(start, end + 1);
    start = end + 1;
  }
}

String _withoutLineEnding(String line) {
  if (line.endsWith('\r\n')) return line.substring(0, line.length - 2);
  if (line.endsWith('\n') || line.endsWith('\r')) {
    return line.substring(0, line.length - 1);
  }
  return line;
}

// ignore_for_file: public_member_api_docs, library_private_types_in_public_api
