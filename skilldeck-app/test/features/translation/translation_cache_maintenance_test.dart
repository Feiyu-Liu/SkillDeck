import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/translation/translation_cache_maintenance.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../../support/fake_app_translation_repository.dart';

void main() {
  test(
    'cleans once per content generation and retries a failed slot',
    () async {
      final cache = MemoryTranslationCache();
      final maintenance = TranslationCacheMaintenance(
        repository: fakeAppTranslationRepository(cache: cache),
        failureReporter: AppFailureReporter(AppDiagnostics.disabled()),
      );
      addTearDown(maintenance.dispose);

      maintenance.accept(_snapshot(1, 'first'));
      await _until(() => cache.evictedGenerations.length == 1);
      expect(cache.evictedGenerations, [('alpha', 'first')]);

      maintenance.accept(_snapshot(2, 'first'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cache.evictedGenerations, hasLength(1));

      cache.evictError = StateError('temporary failure');
      maintenance.accept(_snapshot(3, 'second'));
      await _until(() => cache.evictedGenerations.length == 2);
      cache.evictError = null;
      maintenance.accept(_snapshot(4, 'second'));
      await _until(() => cache.evictedGenerations.length == 3);
      expect(cache.evictedGenerations.last, ('alpha', 'second'));
    },
  );

  test('coalesces rapid revisions to the latest hash', () async {
    final cache = MemoryTranslationCache();
    final maintenance = TranslationCacheMaintenance(
      repository: fakeAppTranslationRepository(cache: cache),
      failureReporter: AppFailureReporter(AppDiagnostics.disabled()),
    );
    addTearDown(maintenance.dispose);

    maintenance.accept(_snapshot(1, 'first'));
    maintenance.accept(_snapshot(2, 'second'));
    maintenance.accept(_snapshot(3, 'third'));
    await _until(() => cache.evictedGenerations.isNotEmpty);
    expect(cache.evictedGenerations, [('alpha', 'third')]);
  });
}

SkillsWorkspaceSnapshot _snapshot(int revision, String hash) =>
    SkillsWorkspaceSnapshot(
      revision: revision,
      projectRoots: const [],
      skills: [
        WorkspaceSkill(
          id: WorkspaceSkillId('alpha'),
          slotKey: 'alpha',
          declaredName: 'alpha',
          displayName: 'Alpha',
          description: 'Test',
          source: SkillSourceProvenance(
            kind: WorkspaceSourceKind.local,
            locator: '/skills/alpha',
          ),
          currentRevision: SkillRevision(
            contentHash: hash,
            fileCount: 1,
            byteSize: 1,
            acquiredAt: DateTime.utc(2026),
          ),
          activations: const [],
        ),
      ],
    );

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}
