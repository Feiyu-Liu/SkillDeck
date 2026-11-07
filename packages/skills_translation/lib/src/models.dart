import 'package:flutter_md/flutter_md.dart';

import 'markdown_source_adapter.dart';
import 'validation.dart';

/// The user-selected portion of a Source Document to translate.
enum TranslationScope {
  /// All translatable prose in the selected document.
  fullDocument,

  /// Only the top-level SKILL.md frontmatter description.
  descriptionOnly,
}

/// The complete immutable Skill document supplied to a Translation Job.
final class SourceDocument {
  /// Creates a Source Document from identity published by Skill Management.
  ///
  /// [slotKey] and [contentHash] are preserved exactly. This package does not
  /// derive, normalize, or otherwise interpret either value.
  SourceDocument({
    required this.slotKey,
    required this.contentHash,
    required this.documentIdentifier,
    required this.content,
  }) {
    requireNonBlank(slotKey, 'slotKey');
    requireNonBlank(contentHash, 'contentHash');
    requireNonBlank(documentIdentifier, 'documentIdentifier');
    requireNonBlank(content, 'content');
  }

  /// The exact Slot Key published by Skill Management.
  final String slotKey;

  /// The exact content hash published for this document revision.
  final String contentHash;

  /// The POSIX relative path that distinguishes this Markdown document.
  final String documentIdentifier;

  /// The complete selected Markdown document content.
  final String content;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceDocument &&
          slotKey == other.slotKey &&
          contentHash == other.contentHash &&
          documentIdentifier == other.documentIdentifier &&
          content == other.content;

  @override
  int get hashCode =>
      Object.hash(slotKey, contentHash, documentIdentifier, content);
}

/// A stable language identifier selected for a Translation Job.
final class TargetLanguage {
  /// Creates a Target Language without normalizing [identifier].
  TargetLanguage(this.identifier) {
    requireNonBlank(identifier, 'identifier');
  }

  /// The stable provider-facing language identifier, not display text.
  final String identifier;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetLanguage && identifier == other.identifier;

  @override
  int get hashCode => identifier.hashCode;
}

/// Ephemeral cumulative output from a running Translation Job.
final class TranslationDraft {
  /// Creates a cumulative Draft of completed source-anchored replacements.
  TranslationDraft({
    required Map<MarkdownBlockId, String> translatedBlocks,
    required this.translatedDescription,
    required this.completedBlockCount,
    required this.totalBlockCount,
  }) : translatedBlocks = Map.unmodifiable(translatedBlocks) {
    for (final translation in this.translatedBlocks.values) {
      requireNonBlank(translation, 'translatedBlocks translation');
    }
    final translatedDescription = this.translatedDescription;
    if (translatedDescription != null) {
      requireNonBlank(translatedDescription, 'translatedDescription');
    }
    if (totalBlockCount < 0 ||
        completedBlockCount <= 0 ||
        completedBlockCount > totalBlockCount ||
        completedBlockCount !=
            this.translatedBlocks.length +
                (translatedDescription == null ? 0 : 1)) {
      throw ArgumentError('Translation Draft progress is inconsistent.');
    }
  }

  /// Completed Markdown block replacements, keyed by shared parser IDs.
  final Map<MarkdownBlockId, String> translatedBlocks;

  /// The completed frontmatter description replacement, when available.
  final String? translatedDescription;

  /// Completed translation units, including the frontmatter description.
  final int completedBlockCount;

  /// Total translation units, including the frontmatter description.
  final int totalBlockCount;

  /// Applies this cumulative Draft to [sourceDocument] for ephemeral display.
  String applyTo(SourceDocument sourceDocument) =>
      TranslationMarkdownSource.parse(
        sourceDocument.content,
        documentIdentifier: sourceDocument.documentIdentifier,
      ).applyReplacements(
        translatedBlocks: translatedBlocks,
        translatedDescription: translatedDescription,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationDraft &&
          _mapsEqual(translatedBlocks, other.translatedBlocks) &&
          translatedDescription == other.translatedDescription &&
          completedBlockCount == other.completedBlockCount &&
          totalBlockCount == other.totalBlockCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      translatedBlocks.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    translatedDescription,
    completedBlockCount,
    totalBlockCount,
  );
}

bool _mapsEqual<K, V>(Map<K, V> left, Map<K, V> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Identifies the Provider and optional model that produced a translation.
final class TranslationProvenance {
  /// Creates result provenance.
  ///
  /// [modelIdentifier] is `null` when the Provider exposes no stable model
  /// identifier. Adapters must not fabricate one.
  TranslationProvenance({
    required this.providerIdentifier,
    this.modelIdentifier,
  }) {
    requireNonBlank(providerIdentifier, 'providerIdentifier');
    final modelIdentifier = this.modelIdentifier;
    if (modelIdentifier != null) {
      requireNonBlank(modelIdentifier, 'modelIdentifier');
    }
  }

  /// The stable identifier for the Translation Provider.
  final String providerIdentifier;

  /// The Provider's stable model identifier, when one is available.
  final String? modelIdentifier;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationProvenance &&
          providerIdentifier == other.providerIdentifier &&
          modelIdentifier == other.modelIdentifier;

  @override
  int get hashCode => Object.hash(providerIdentifier, modelIdentifier);
}

/// The single terminal outcome of a Translation Job.
sealed class TranslationJobOutcome {
  const TranslationJobOutcome();
}

/// The complete successful output of one scoped Translation Job.
final class CompletedTranslation extends TranslationJobOutcome {
  /// Creates a Completed Translation eligible for future cache storage.
  CompletedTranslation({
    required this.slotKey,
    required this.contentHash,
    required this.documentIdentifier,
    required this.targetLanguage,
    required this.translatedContent,
    required this.provenance,
    this.scope = TranslationScope.fullDocument,
  }) {
    requireNonBlank(slotKey, 'slotKey');
    requireNonBlank(contentHash, 'contentHash');
    requireNonBlank(documentIdentifier, 'documentIdentifier');
    requireNonBlank(translatedContent, 'translatedContent');
  }

  /// The exact Slot Key from the Source Document.
  final String slotKey;

  /// The exact content hash from the Source Document.
  final String contentHash;

  /// The exact document identifier from the Source Document.
  final String documentIdentifier;

  /// The Target Language requested for the Job.
  final TargetLanguage targetLanguage;

  /// The complete translated document, or only its translated description.
  final String translatedContent;

  /// The Provider and model provenance for this result.
  final TranslationProvenance provenance;

  /// Whether [translatedContent] is a full document or only its description.
  final TranslationScope scope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompletedTranslation &&
          slotKey == other.slotKey &&
          contentHash == other.contentHash &&
          documentIdentifier == other.documentIdentifier &&
          targetLanguage == other.targetLanguage &&
          translatedContent == other.translatedContent &&
          scope == other.scope &&
          provenance == other.provenance;

  @override
  int get hashCode => Object.hash(
    slotKey,
    contentHash,
    documentIdentifier,
    targetLanguage,
    translatedContent,
    scope,
    provenance,
  );
}

/// The terminal outcome when a Translation Job cannot complete.
final class TranslationFailure extends TranslationJobOutcome {
  /// Creates a Failure with a sanitized [reason].
  ///
  /// Provider error fields are shown verbatim only on explicit request in the
  /// App. They may echo sensitive data and must never be logged or persisted.
  TranslationFailure({
    required this.code,
    required this.reason,
    this.providerErrorCode,
    this.providerErrorMessage,
  }) {
    requireNonBlank(reason, 'reason');
  }

  /// Stable machine-readable category for this failure.
  final TranslationFailureCode code;

  /// A sanitized reason suitable for presentation to the user.
  final String reason;

  /// The Provider's own error code (or type), not the stable [code].
  final String? providerErrorCode;

  /// The Provider's own message, potentially including echoed user data.
  final String? providerErrorMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationFailure &&
          code == other.code &&
          reason == other.reason &&
          providerErrorCode == other.providerErrorCode &&
          providerErrorMessage == other.providerErrorMessage;

  @override
  int get hashCode =>
      Object.hash(code, reason, providerErrorCode, providerErrorMessage);
}

/// Stable failure categories independent of a concrete LLM SDK or Provider.
enum TranslationFailureCode {
  /// Provider construction or caller-supplied configuration is invalid.
  invalidConfiguration,

  /// The configured credential was rejected.
  authenticationFailed,

  /// The credential lacks access to the requested operation.
  accessDenied,

  /// The Provider is currently rate limiting requests.
  rateLimited,

  /// The Provider rejected a syntactically valid request.
  requestRejected,

  /// The remote Provider is unavailable.
  providerUnavailable,

  /// The Provider endpoint could not be reached.
  networkUnavailable,

  /// The request exceeded its inactivity timeout.
  timedOut,

  /// The Provider returned incomplete or malformed output.
  invalidResponse,

  /// The failure did not map to a stable category.
  unknown,
}

/// The distinct non-failure terminal outcome of Job Cancellation.
final class TranslationJobCancellation extends TranslationJobOutcome {
  /// Creates a Job Cancellation outcome.
  const TranslationJobCancellation();

  @override
  bool operator ==(Object other) => other is TranslationJobCancellation;

  @override
  int get hashCode => runtimeType.hashCode;
}
