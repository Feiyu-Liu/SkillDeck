// ignore_for_file: public_member_api_docs

import 'package:flutter_md/flutter_md.dart';

import 'markdown_source_adapter.dart';

const String translationUnitSeparator = '\n\n%%\n\n';

final RegExp _standaloneSeparatorLine = RegExp(
  r'(?:^|\r\n|\n|\r)[ \t]*%%[ \t]*(?=\r\n|\n|\r|$)',
);

final RegExp _streamingSeparatorLine = RegExp(
  r'^[ \t]*%%[ \t]*(?:\r\n|\n|\r)',
  multiLine: true,
);

final RegExp _completedSeparatorLine = RegExp(
  r'^[ \t]*%%[ \t]*(?:(?:\r\n|\n|\r)|$)',
  multiLine: true,
);

final class TranslationUnit {
  const TranslationUnit._({
    required this.wireId,
    required this.source,
    required this.markdownBlockId,
  });

  factory TranslationUnit.description(String source) => TranslationUnit._(
    wireId: frontmatterDescriptionWireId,
    source: source,
    markdownBlockId: null,
  );

  factory TranslationUnit.markdown(TranslationMarkdownBlock block) {
    final wireId = block.id.value;
    if (wireId == frontmatterDescriptionWireId || !wireId.startsWith('b:')) {
      throw StateError('The Markdown parser returned an invalid block ID.');
    }
    return TranslationUnit._(
      wireId: wireId,
      source: block.source,
      markdownBlockId: block.id,
    );
  }

  final String wireId;
  final String source;
  final MarkdownBlockId? markdownBlockId;

  bool get isDescription => markdownBlockId == null;
}

final class TranslationSegment {
  const TranslationSegment({required this.id, required this.units});

  final String id;
  final List<TranslationUnit> units;

  String get systemPromptInstructions {
    if (units.length == 1) {
      return '''
## Output Contract
This request contains one source block. Return only its translated block, with
no block separator, alternative, repetition, or commentary.
''';
    }
    return '''
## Output Contract
The user message contains multiple source blocks separated by standalone `%%`
lines. Return the same number of translated blocks in the same order, separated
by the same number of standalone `%%` lines. Keep every separator on its own
line, with no text before or after it.
''';
  }

  String userPrompt(String targetLanguageIdentifier) {
    if (units.length == 1) {
      return '''
Translate to $targetLanguageIdentifier (output translation only):

${units.single.source}
''';
    }
    return '''
Translate to $targetLanguageIdentifier:

${units.map((unit) => unit.source).join(translationUnitSeparator)}
''';
  }
}

List<TranslationSegment> createTranslationSegments({
  required TranslationMarkdownSource document,
  required int characterBudget,
  bool descriptionOnly = false,
}) {
  final segments = <List<TranslationUnit>>[];
  final description = document.descriptionSource;
  if (description != null) {
    segments.add(<TranslationUnit>[TranslationUnit.description(description)]);
  }
  if (descriptionOnly) {
    return List<TranslationSegment>.unmodifiable([
      for (var index = 0; index < segments.length; index += 1)
        TranslationSegment(
          id: 'segment-${index + 1}',
          units: List<TranslationUnit>.unmodifiable(segments[index]),
        ),
    ]);
  }

  var pending = <TranslationUnit>[];
  var pendingCharacters = 0;

  void flushPending() {
    if (pending.isEmpty) return;
    segments.add(pending);
    pending = <TranslationUnit>[];
    pendingCharacters = 0;
  }

  for (final block in document.blocks) {
    final unit = TranslationUnit.markdown(block);
    final characters = unit.source.runes.length;
    final separatorCharacters =
        pending.isEmpty ? 0 : translationUnitSeparator.runes.length;
    if (_standaloneSeparatorLine.hasMatch(unit.source)) {
      flushPending();
      segments.add(<TranslationUnit>[unit]);
      continue;
    }
    if (pending.isNotEmpty &&
        pendingCharacters + separatorCharacters + characters >
            characterBudget) {
      flushPending();
    }
    pending.add(unit);
    pendingCharacters +=
        (pending.length == 1 ? 0 : translationUnitSeparator.runes.length) +
        characters;
    if (characters > characterBudget) flushPending();
  }
  flushPending();

  return List<TranslationSegment>.unmodifiable([
    for (var index = 0; index < segments.length; index += 1)
      TranslationSegment(
        id: 'segment-${index + 1}',
        units: List<TranslationUnit>.unmodifiable(segments[index]),
      ),
  ]);
}

final class DecodedTranslationBlock {
  const DecodedTranslationBlock({
    required this.unit,
    required this.translation,
  });

  final TranslationUnit unit;
  final String translation;
}

final class TranslationSegmentDecoder {
  TranslationSegmentDecoder(this.segment);

  final TranslationSegment segment;
  final StringBuffer _buffer = StringBuffer();
  var _partStart = 0;
  var _decodedUnitCount = 0;
  var _completed = false;

  int get decodedUnitCount => _decodedUnitCount;

  List<DecodedTranslationBlock> add(String delta) {
    if (_completed) throw _failure();
    _buffer.write(delta);
    if (segment.units.length == 1) {
      return const <DecodedTranslationBlock>[];
    }
    return _transaction(() => _consumeSeparators(_streamingSeparatorLine));
  }

  List<DecodedTranslationBlock> complete() {
    if (_completed) throw _failure();
    if (segment.units.length == 1) {
      return _transaction(() {
        final decoded = _decodePart(_buffer.toString());
        _completed = true;
        return List<DecodedTranslationBlock>.unmodifiable([decoded]);
      });
    }
    return _transaction(() {
      final decoded = <DecodedTranslationBlock>[
        ..._consumeSeparators(_completedSeparatorLine),
      ];
      if (_decodedUnitCount != segment.units.length - 1) throw _failure();
      decoded.add(_decodePart(_buffer.toString().substring(_partStart)));
      _completed = true;
      return List<DecodedTranslationBlock>.unmodifiable(decoded);
    });
  }

  List<DecodedTranslationBlock> _transaction(
    List<DecodedTranslationBlock> Function() action,
  ) {
    final originalPartStart = _partStart;
    final originalDecodedUnitCount = _decodedUnitCount;
    try {
      return action();
    } on TranslationProtocolException {
      _partStart = originalPartStart;
      _decodedUnitCount = originalDecodedUnitCount;
      throw TranslationProtocolException(
        completedUnitCount: originalDecodedUnitCount,
      );
    }
  }

  List<DecodedTranslationBlock> _consumeSeparators(RegExp separatorPattern) {
    final source = _buffer.toString();
    final decoded = <DecodedTranslationBlock>[];
    while (true) {
      final separator = separatorPattern.firstMatch(
        source.substring(_partStart),
      );
      if (separator == null) break;
      final separatorStart = _partStart + separator.start;
      final separatorEnd = _partStart + separator.end;
      if (_decodedUnitCount >= segment.units.length - 1) throw _failure();
      decoded.add(_decodePart(source.substring(_partStart, separatorStart)));
      _partStart = separatorEnd;
    }
    return List<DecodedTranslationBlock>.unmodifiable(decoded);
  }

  DecodedTranslationBlock _decodePart(String source) {
    final translation = source.trim();
    if (translation.isEmpty || _decodedUnitCount >= segment.units.length) {
      throw _failure();
    }
    final block = DecodedTranslationBlock(
      unit: segment.units[_decodedUnitCount],
      translation: translation,
    );
    _decodedUnitCount += 1;
    return block;
  }

  TranslationProtocolException _failure() =>
      TranslationProtocolException(completedUnitCount: _decodedUnitCount);
}

final class TranslationProtocolException implements Exception {
  const TranslationProtocolException({this.completedUnitCount = 0});

  final int completedUnitCount;
}
