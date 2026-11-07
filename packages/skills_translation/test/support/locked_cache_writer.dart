import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_translation/skills_translation.dart';

void main() {
  test('writes while coordinated by the parent process', () async {
    const root = String.fromEnvironment('CACHE_ROOT');
    if (root.isEmpty) throw StateError('CACHE_ROOT is required.');
    print('cache-child-ready');
    await FileTranslationCache(rootDirectory: Directory(root)).saveOrReplace(
      CompletedTranslation(
        slotKey: 'child-slot',
        contentHash: 'child-hash',
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: 'child translation',
        provenance: TranslationProvenance(
          providerIdentifier: 'child-provider',
          modelIdentifier: 'child-model',
        ),
      ),
    );
    print('cache-child-done');
  });
}
