import 'dart:async';

import 'models.dart';

/// Performs scoped Translation Jobs through a replaceable adapter.
///
/// Concrete adapters keep SDK and transport types private. Expected provider
/// and transport problems become a [TranslationFailure] instead of escaping
/// through [start] or the Draft stream.
abstract interface class TranslationProvider {
  /// Starts one user-initiated Job for [sourceDocument] and [targetLanguage].
  ///
  /// Providers may segment a document internally, but callers observe one Job
  /// and at most one Completed Translation. Implementations must not retry,
  /// queue, or start work automatically in response to connectivity or app
  /// lifecycle changes.
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  });
}

/// A live, explicitly cancellable scoped Translation Job.
///
/// [drafts] is a broadcast stream of cumulative snapshots. It does not replay
/// earlier Drafts, and expected failures are reported only through [result],
/// never as Stream errors. The Draft stream closes before [result] completes.
/// Cancelling a Draft subscription does not cancel this Job; callers must invoke
/// [cancel] when the Source Document closes or the Target Language changes.
abstract interface class TranslationJob {
  /// Cumulative, ephemeral Translation Drafts emitted while the Job runs.
  Stream<TranslationDraft> get drafts;

  /// The single terminal outcome of this Job.
  Future<TranslationJobOutcome> get result;

  /// Explicitly cancels this Job and awaits cancellation cleanup.
  ///
  /// Cancellation is idempotent. When an active Job is cancelled, this Future
  /// completes only after [drafts] closes and [result] resolves to
  /// [TranslationJobCancellation]. Cancelling a terminal Job succeeds without
  /// changing its outcome.
  Future<void> cancel();
}
