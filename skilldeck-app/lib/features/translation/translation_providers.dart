import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_translation/skills_translation.dart';

final appTranslationRepositoryProvider = Provider<AppTranslationRepository>((
  ref,
) {
  throw UnimplementedError('An AppTranslationRepository override is required.');
});

final appTranslationCacheCleanupProvider = Provider<AppTranslationCacheCleanup>(
  (ref) => AppTranslationCacheCleanup(
    repository: ref.watch(appTranslationRepositoryProvider),
    failureReporter: ref.watch(appFailureReporterProvider),
  ),
);

final class AppTranslationCacheCleanup {
  const AppTranslationCacheCleanup({
    required AppTranslationRepository repository,
    required AppFailureReporter failureReporter,
  }) : _repository = repository,
       _failureReporter = failureReporter;

  final AppTranslationRepository _repository;
  final AppFailureReporter _failureReporter;

  Future<bool> deleteSlot(String slotKey) async {
    try {
      await _repository.deleteSlot(slotKey: slotKey);
      return true;
    } on Object catch (error, stackTrace) {
      _failureReporter.capture(
        error,
        stackTrace,
        operationKey: 'deleteSkillTranslationCache',
        message: AppFailureMessage.io,
        recoveryPolicy: AppRecoveryPolicy.none,
      );
      return false;
    }
  }
}

/// App-composition seam for the currently visible immutable Skill document.
///
/// Translation does not import the Skills feature's ViewModel implementation;
/// the executable and test shells map their chosen selection source here.
final activeTranslationRequestProvider = Provider<SourceDocument?>(
  (ref) => null,
);
