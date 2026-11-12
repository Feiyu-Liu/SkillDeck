import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/settings/presentation/views/settings_screen.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';

import '../support/fake_app_translation_repository.dart';
import '../support/fake_skill_browser_repository.dart';

final _catalogProvider =
    NotifierProvider<_Catalog, AsyncValue<InstalledSkillCatalog>>(_Catalog.new);

final class _Catalog extends Notifier<AsyncValue<InstalledSkillCatalog>> {
  @override
  AsyncValue<InstalledSkillCatalog> build() => const AsyncLoading();

  void update(InstalledSkillCatalog catalog) => state = AsyncData(catalog);
}

ProviderContainer _container(FakeSkillBrowserRepository repository) =>
    ProviderContainer(
      overrides: [
        desktopSupportedProvider.overrideWithValue(true),
        skillBrowserRepositoryProvider.overrideWithValue(repository),
        workspaceInstalledSkillCatalogProvider.overrideWith(
          (ref) => ref.watch(_catalogProvider),
        ),
        appTranslationRepositoryProvider.overrideWithValue(
          fakeAppTranslationRepository(),
        ),
        activeTranslationRequestProvider.overrideWith((ref) {
          ref.watch(skillBrowserCatalogProvider);
          return null;
        }),
      ],
    );

void main() {
  testWidgets('Settings lazy flush after a six-Skill update defers selection '
      'mutation until after build', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      documents: {'alpha': '# Alpha'},
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final browser = container.read(skillBrowserViewModelProvider.notifier);
    container
        .read(_catalogProvider.notifier)
        .update(
          InstalledSkillCatalog(
            revision: 477,
            skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha')],
          ),
        );
    container.read(workspaceInstalledSkillCatalogProvider);
    await tester.runAsync(() => pumpEventQueue());
    expect(browser.documentStatus, DocumentStatus.ready);

    // The update dirties the projection, but does not read it. Opening
    // Settings must perform the lazy flush, just as in issue #36's stack.
    final skills = List.generate(
      6,
      (index) => testSkill(
        slotKey: index == 0 ? 'alpha' : 'skill-$index',
        displayName: 'Updated $index',
      ),
    );
    container
        .read(_catalogProvider.notifier)
        .update(InstalledSkillCatalog(revision: 478, skills: skills));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(browser.selectedSkill?.displayName, 'Updated 0');
    expect(container.read(skillBrowserCatalogProvider).revision, 478);
    expect(browser.document, '# Alpha');
    expect(repository.documentReads, ['alpha']);
  });

  test('only the newest queued catalog starts a document read', () async {
    final repository = FakeSkillBrowserRepository(
      documents: {'beta': '# Beta'},
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final browser = container.read(skillBrowserViewModelProvider.notifier);
    for (final slot in ['alpha', 'beta']) {
      container
          .read(_catalogProvider.notifier)
          .update(
            InstalledSkillCatalog(
              revision: slot == 'alpha' ? 478 : 479,
              skills: [testSkill(slotKey: slot, displayName: slot)],
            ),
          );
      container.read(workspaceInstalledSkillCatalogProvider);
    }
    await pumpEventQueue();
    expect(browser.selectedSkill?.slotKey, 'beta');
    expect(browser.document, '# Beta');
    expect(repository.documentReads, ['beta']);
  });

  test('disposal cancels queued selection reconciliation', () async {
    final repository = FakeSkillBrowserRepository(
      documents: {'alpha': '# Alpha'},
    );
    final container = _container(repository);
    container.read(skillBrowserViewModelProvider);
    container
        .read(_catalogProvider.notifier)
        .update(
          InstalledSkillCatalog(
            revision: 478,
            skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha')],
          ),
        );
    container.read(workspaceInstalledSkillCatalogProvider);
    container.dispose();
    await pumpEventQueue();
    expect(repository.documentReads, isEmpty);
  });

  test(
    'a previous document read cannot publish after a newer catalog',
    () async {
      final oldDocument = Completer<String>();
      final repository =
          FakeSkillBrowserRepository(
              documents: {'alpha': '# Alpha', 'beta': '# Beta'},
            )
            ..readDocumentHandler = (skill) => skill.slotKey == 'alpha'
                ? oldDocument.future
                : Future.value('# Beta');
      final container = _container(repository);
      addTearDown(container.dispose);
      final browser = container.read(skillBrowserViewModelProvider.notifier);
      void publish(String slot, int revision) {
        container
            .read(_catalogProvider.notifier)
            .update(
              InstalledSkillCatalog(
                revision: revision,
                skills: [testSkill(slotKey: slot, displayName: slot)],
              ),
            );
        container.read(workspaceInstalledSkillCatalogProvider);
      }

      publish('alpha', 478);
      await pumpEventQueue();
      expect(repository.documentReads, ['alpha']);
      publish('beta', 479);
      oldDocument.complete('# Old Alpha');
      await pumpEventQueue();
      expect(browser.selectedSkill?.slotKey, 'beta');
      expect(browser.document, '# Beta');
    },
  );

  test(
    'overlapping revisions of the same Skill keep the latest load active',
    () async {
      final oldDocument = Completer<String>();
      final newDocument = Completer<String>();
      final hashes = <String>[];
      final repository = FakeSkillBrowserRepository(documents: {'alpha': ''})
        ..readDocumentHandler = (skill) {
          hashes.add(skill.contentHash);
          return skill.contentHash == 'a' * 64
              ? oldDocument.future
              : newDocument.future;
        };
      final container = _container(repository);
      addTearDown(container.dispose);
      final browser = container.read(skillBrowserViewModelProvider.notifier);
      for (final hash in ['a', 'b']) {
        container
            .read(_catalogProvider.notifier)
            .update(
              InstalledSkillCatalog(
                revision: hash == 'a' ? 478 : 479,
                skills: [
                  testSkill(
                    slotKey: 'alpha',
                    displayName: 'Alpha',
                    contentHash: hash * 64,
                  ),
                ],
              ),
            );
        container.read(workspaceInstalledSkillCatalogProvider);
        await pumpEventQueue();
      }
      oldDocument.complete('# Old Alpha');
      await pumpEventQueue();
      // The old read finishing must not clear the newer same-ID loading marker.
      await browser.selectSkill(browser.selectedSkill!.id);
      expect(hashes, ['a' * 64, 'b' * 64]);
      expect(browser.document, isNull);
      newDocument.complete('# Latest Alpha');
      await pumpEventQueue();
      expect(browser.document, '# Latest Alpha');
      expect(browser.selectedSkill?.contentHash, 'b' * 64);
    },
  );

  test(
    'a user selection made before queued reconciliation is preserved',
    () async {
      final repository = FakeSkillBrowserRepository(
        documents: {'alpha': '# Alpha', 'beta': '# Beta'},
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final browser = container.read(skillBrowserViewModelProvider.notifier);
      final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
      final beta = testSkill(slotKey: 'beta', displayName: 'Beta');
      for (final revision in [478, 479]) {
        container
            .read(_catalogProvider.notifier)
            .update(
              InstalledSkillCatalog(revision: revision, skills: [alpha, beta]),
            );
        container.read(workspaceInstalledSkillCatalogProvider);
        if (revision == 478) await pumpEventQueue();
      }
      await browser.selectSkill(beta.id);
      await pumpEventQueue();
      expect(browser.selectedSkill?.id, beta.id);
      expect(browser.document, '# Beta');
    },
  );
}
