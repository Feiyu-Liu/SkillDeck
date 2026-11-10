import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_translation/skills_translation.dart';

final class TranslationScopePreferenceStore {
  TranslationScopePreferenceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.translation.last_scope';

  final SharedPreferencesAsync _preferences;

  Future<TranslationScope> read() async {
    try {
      final value = await _preferences.getString(preferenceKey);
      return TranslationScope.values.firstWhere(
        (scope) => scope.name == value,
        orElse: () => TranslationScope.fullDocument,
      );
    } on Object {
      return TranslationScope.fullDocument;
    }
  }

  Future<void> write(TranslationScope scope) =>
      _preferences.setString(preferenceKey, scope.name);
}

final translationScopePreferenceStoreProvider =
    Provider<TranslationScopePreferenceStore>(
      (ref) => TranslationScopePreferenceStore(),
    );

final initialTranslationScopeProvider = Provider<TranslationScope>(
  (ref) => TranslationScope.fullDocument,
);

final translationScopePreferenceProvider =
    NotifierProvider<TranslationScopePreferenceController, TranslationScope>(
      TranslationScopePreferenceController.new,
    );

final class TranslationScopePreferenceController
    extends Notifier<TranslationScope> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  TranslationScope build() => ref.read(initialTranslationScopeProvider);

  void select(TranslationScope scope) {
    state = scope;
    final store = ref.read(translationScopePreferenceStoreProvider);
    // Serialize rapid selections so the last choice is also the last write.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await store.write(scope);
      } on Object {
        // Keep the in-memory choice when this optional preference cannot save.
      }
    });
    unawaited(_pendingWrite);
  }
}
