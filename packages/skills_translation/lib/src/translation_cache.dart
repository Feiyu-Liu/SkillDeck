import 'models.dart';
import 'validation.dart';

/// Content-addressed identity for one scoped Completed Translation.
final class TranslationCacheKey {
  /// Creates a key from identity owned by Skill Management and Translation.
  TranslationCacheKey({
    required this.slotKey,
    required this.contentHash,
    required this.documentIdentifier,
    required this.targetLanguage,
    this.scope = TranslationScope.fullDocument,
  }) {
    requireNonBlank(slotKey, 'slotKey');
    requireNonBlank(contentHash, 'contentHash');
    requireNonBlank(documentIdentifier, 'documentIdentifier');
  }

  /// The exact Slot Key published by Skill Management.
  final String slotKey;

  /// The exact content hash for this document revision.
  final String contentHash;

  /// The exact POSIX relative Markdown path supplied by the app.
  final String documentIdentifier;

  /// The requested Target Language.
  final TargetLanguage targetLanguage;

  /// The completed portion of this Source Document.
  final TranslationScope scope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationCacheKey &&
          slotKey == other.slotKey &&
          contentHash == other.contentHash &&
          documentIdentifier == other.documentIdentifier &&
          targetLanguage == other.targetLanguage &&
          scope == other.scope;

  @override
  int get hashCode => Object.hash(
    slotKey,
    contentHash,
    documentIdentifier,
    targetLanguage,
    scope,
  );
}

/// Disposable persistence for complete translations outside the engine root.
abstract interface class TranslationCache {
  /// Reads an exact content-addressed entry, or returns `null` on a miss.
  Future<CompletedTranslation?> read(TranslationCacheKey key);

  /// Atomically saves or replaces the result for the same document/language/scope.
  Future<void> saveOrReplace(CompletedTranslation value);

  /// Deletes cached output whose content hash is no longer current.
  Future<void> evictStale({
    required String slotKey,
    required String currentContentHash,
  });

  /// Deletes all translation data associated with one Slot Key.
  Future<void> deleteSlot({required String slotKey});

  /// Deletes every Completed Translation while retaining the cache root.
  Future<void> clear();
}
