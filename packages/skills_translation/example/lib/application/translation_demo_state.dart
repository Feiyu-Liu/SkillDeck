import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';

const Object _notProvided = Object();

enum TranslationDemoPhase {
  idle,
  loadingSource,
  translating,
  cancelling,
  completed,
  failed,
  cancelled,
}

final class TranslationDemoState {
  const TranslationDemoState({
    required this.config,
    required this.sourceContent,
    required this.sourcePath,
    required this.translatedContent,
    required this.phase,
    required this.statusMessage,
    required this.provenance,
  });

  factory TranslationDemoState.initial() => TranslationDemoState(
        config: TranslationDemoConfig.initial(),
        sourceContent: _sampleMarkdown,
        sourcePath: null,
        translatedContent: '',
        phase: TranslationDemoPhase.idle,
        statusMessage: 'Ready. Translation starts only when you request it.',
        provenance: null,
      );

  final TranslationDemoConfig config;
  final String sourceContent;
  final String? sourcePath;
  final String translatedContent;
  final TranslationDemoPhase phase;
  final String? statusMessage;
  final TranslationProvenance? provenance;

  bool get isBusy => switch (phase) {
        TranslationDemoPhase.loadingSource ||
        TranslationDemoPhase.translating ||
        TranslationDemoPhase.cancelling =>
          true,
        _ => false,
      };

  bool get canCancel => phase == TranslationDemoPhase.translating;

  TranslationDemoState copyWith({
    TranslationDemoConfig? config,
    String? sourceContent,
    Object? sourcePath = _notProvided,
    String? translatedContent,
    TranslationDemoPhase? phase,
    Object? statusMessage = _notProvided,
    Object? provenance = _notProvided,
  }) =>
      TranslationDemoState(
        config: config ?? this.config,
        sourceContent: sourceContent ?? this.sourceContent,
        sourcePath: identical(sourcePath, _notProvided)
            ? this.sourcePath
            : sourcePath as String?,
        translatedContent: translatedContent ?? this.translatedContent,
        phase: phase ?? this.phase,
        statusMessage: identical(statusMessage, _notProvided)
            ? this.statusMessage
            : statusMessage as String?,
        provenance: identical(provenance, _notProvided)
            ? this.provenance
            : provenance as TranslationProvenance?,
      );
}

const String _sampleMarkdown = '''---
name: translation-example
description: A small Markdown document for trying live translation.
---

# Translate a Skill

This example preserves **Markdown structure**, links, and inline `code`.

```dart
void main() {
  print('Fenced code is never sent for translation.');
}
```
''';
