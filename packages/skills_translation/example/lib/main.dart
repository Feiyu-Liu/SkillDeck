import 'package:flutter/cupertino.dart';
import 'package:skills_translation_example/app.dart';
import 'package:skills_translation_example/application/translation_demo_controller.dart';
import 'package:skills_translation_example/infrastructure/markdown_document_loader.dart';
import 'package:skills_translation_example/infrastructure/translation_demo_repository.dart';

void main() {
  runApp(
    SkillsTranslationExampleApp(
      controller: TranslationDemoController(
        repository: const LlmTranslationDemoRepository(),
        documentLoader: const FileSelectorMarkdownDocumentLoader(),
      ),
    ),
  );
}
