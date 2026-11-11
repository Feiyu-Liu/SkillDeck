import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  test('load exposes loading and then an empty ready catalog', () async {
    final completer = Completer<InstalledSkillCatalog>();
    final repository = FakeSkillBrowserRepository()
      ..openHandler = () => completer.future;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    final loading = viewModel.load();
    expect(viewModel.catalogStatus, CatalogStatus.loading);

    completer.complete(InstalledSkillCatalog(revision: 3, skills: const []));
    await loading;

    expect(viewModel.catalogStatus, CatalogStatus.ready);
    expect(viewModel.skills, isEmpty);
    expect(viewModel.revision, 3);
  });

  test('load exposes a safe repository failure', () async {
    final repository = FakeSkillBrowserRepository()
      ..openHandler = () async => throw WorkspaceException(
        operation: WorkspaceOperationKind.open,
        code: WorkspaceErrorCode.stateCorrupt,
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    await viewModel.load();

    expect(viewModel.catalogStatus, CatalogStatus.failure);
    expect(viewModel.catalogFailure?.codeKey, 'stateCorrupt');
    expect(viewModel.catalogFailure?.operationKey, 'open');
  });

  test('load selects the first skill and reads its document', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 2, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    await viewModel.load();

    expect(viewModel.selectedSkill, alpha);
    expect(viewModel.documentStatus, DocumentStatus.ready);
    expect(viewModel.document, '# Alpha');
    expect(repository.documentReads, ['alpha']);
  });

  test('lists and selects nested Markdown documents', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 2, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
      additionalDocuments: const {
        'alpha': {'references/guide.md': '# Guide'},
      },
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    await viewModel.load();
    await viewModel.selectDocument('references/guide.md');

    expect(viewModel.documentCatalogStatus, DocumentCatalogStatus.ready);
    expect(viewModel.documents.map((document) => document.relativePath), [
      'SKILL.md',
      'references/guide.md',
    ]);
    expect(viewModel.selectedDocumentPath, 'references/guide.md');
    expect(viewModel.document, '# Guide');
    expect(repository.documentPathReads, [
      (slotKey: 'alpha', relativePath: 'SKILL.md'),
      (slotKey: 'alpha', relativePath: 'references/guide.md'),
    ]);
  });

  test(
    'reads and exposes the content hash from the selected manifest entry',
    () async {
      const manifestHash = 'manifest-hash';
      final alpha = testSkill(
        slotKey: 'alpha',
        displayName: 'Alpha',
        contentHash: 'snapshot-hash',
      );
      final repository =
          FakeSkillBrowserRepository(
              catalog: InstalledSkillCatalog(revision: 2, skills: [alpha]),
              documents: {'alpha': '# Alpha'},
            )
            ..listDocumentsHandler = (_) async => const [
              SkillDocumentEntry(
                relativePath: 'SKILL.md',
                name: 'SKILL.md',
                contentHash: manifestHash,
              ),
            ];
      final container = _container(repository);
      addTearDown(container.dispose);
      final viewModel = container.read(skillBrowserViewModelProvider.notifier);

      await viewModel.load();

      expect(viewModel.documentContentHash, manifestHash);
      expect(repository.documentContentHashReads, [manifestHash]);
    },
  );

  test('keeps the latest document when reads finish out of order', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final first = Completer<String>();
    final second = Completer<String>();
    final repository =
        FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 2, skills: [alpha]),
            documents: {'alpha': '# Alpha'},
            additionalDocuments: const {
              'alpha': {
                'references/first.md': '# First',
                'references/second.md': '# Second',
              },
            },
          )
          ..readDocumentPathHandler = (skill, path) => switch (path) {
            'SKILL.md' => Future.value('# Alpha'),
            'references/first.md' => first.future,
            'references/second.md' => second.future,
            _ => Future.error(StateError('Unknown document')),
          };
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();

    final firstRead = viewModel.selectDocument('references/first.md');
    final secondRead = viewModel.selectDocument('references/second.md');
    second.complete('# Second');
    await secondRead;
    first.complete('# First');
    await firstRead;

    expect(viewModel.selectedDocumentPath, 'references/second.md');
    expect(viewModel.document, '# Second');
  });

  test('refresh preserves a selected document that still exists', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final changedAlpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha',
      contentHash: List.filled(64, 'b').join(),
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
      additionalDocuments: const {
        'alpha': {'references/guide.md': '# Before'},
      },
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();
    await viewModel.selectDocument('references/guide.md');
    repository.additionalDocuments['alpha']!['references/guide.md'] = '# After';
    repository.refreshHandler = () async =>
        InstalledSkillCatalog(revision: 2, skills: [changedAlpha]);

    await viewModel.refresh();

    expect(viewModel.selectedDocumentPath, 'references/guide.md');
    expect(viewModel.document, '# After');
  });

  test('keeps SKILL.md readable while the document list is retried', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    var listCalls = 0;
    final repository =
        FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
            documents: {'alpha': '# Alpha'},
          )
          ..listDocumentsHandler = (skill) async {
            listCalls += 1;
            if (listCalls == 1) {
              throw WorkspaceException(
                code: WorkspaceErrorCode.documentUnavailable,
                operation: WorkspaceOperationKind.readDocument,
              );
            }
            return const [
              SkillDocumentEntry(
                relativePath: 'SKILL.md',
                name: 'SKILL.md',
                contentHash: 'manifest-hash',
              ),
            ];
          };
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    await viewModel.load();

    expect(viewModel.documentCatalogStatus, DocumentCatalogStatus.failure);
    expect(viewModel.documentStatus, DocumentStatus.ready);
    expect(viewModel.document, '# Alpha');

    await viewModel.retryDocumentCatalog();

    expect(viewModel.documentCatalogStatus, DocumentCatalogStatus.ready);
    expect(viewModel.documents.single.relativePath, 'SKILL.md');
    expect(viewModel.document, '# Alpha');
  });

  test('selection exposes document failure and explicit retry', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final beta = testSkill(slotKey: 'beta', displayName: 'Beta');
    final repository =
        FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha, beta]),
            documents: {'alpha': '# Alpha', 'beta': '# Beta'},
          )
          ..documentErrors['beta'] = WorkspaceException(
            code: WorkspaceErrorCode.documentUnavailable,
            operation: WorkspaceOperationKind.readDocument,
          );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();

    await viewModel.selectSkill(beta.id);

    expect(viewModel.selectedSkill, beta);
    expect(viewModel.documentStatus, DocumentStatus.failure);
    expect(viewModel.documentFailure?.message, AppFailureMessage.documentRead);

    repository.documentErrors.remove('beta');
    await viewModel.retryDocument();

    expect(viewModel.documentStatus, DocumentStatus.ready);
    expect(viewModel.document, '# Beta');
  });

  test('selection coalesces duplicate document reads while loading', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final beta = testSkill(slotKey: 'beta', displayName: 'Beta');
    final betaDocument = Completer<String>();
    final repository =
        FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha, beta]),
            documents: {'alpha': '# Alpha'},
          )
          ..readDocumentHandler = (skill) => switch (skill.slotKey) {
            'alpha' => Future<String>.value('# Alpha'),
            'beta' => betaDocument.future,
            _ => Future<String>.error(StateError('Unknown test skill')),
          };
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();

    final firstSelection = viewModel.selectSkill(beta.id);
    final duplicateSelection = viewModel.selectSkill(beta.id);
    await Future<void>.value();
    expect(repository.documentReads, ['alpha', 'beta']);

    betaDocument.complete('# Beta');
    await Future.wait([firstSelection, duplicateSelection]);

    expect(viewModel.document, '# Beta');
    expect(repository.documentReads, ['alpha', 'beta']);
  });

  test('refresh preserves a selected unchanged document', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final beta = testSkill(slotKey: 'beta', displayName: 'Beta');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha, beta]),
      documents: {'alpha': '# Alpha', 'beta': '# Beta'},
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();
    await viewModel.selectSkill(beta.id);
    repository.refreshHandler = () async =>
        InstalledSkillCatalog(revision: 2, skills: [beta, alpha]);
    final readsBeforeRefresh = repository.documentReads.length;

    await viewModel.refresh();

    expect(repository.refreshCalls, 1);
    expect(viewModel.revision, 2);
    expect(viewModel.selectedSkill?.slotKey, 'beta');
    expect(viewModel.document, '# Beta');
    expect(repository.documentReads.length, readsBeforeRefresh);
  });

  test('refresh reloads the document when its content hash changes', () async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
    final changedAlpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha',
      contentHash: List.filled(64, 'b').join(),
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Before'},
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();
    repository.documents['alpha'] = '# After';
    repository.refreshHandler = () async =>
        InstalledSkillCatalog(revision: 2, skills: [changedAlpha]);

    await viewModel.refresh();

    expect(viewModel.document, '# After');
    expect(repository.documentReads, ['alpha', 'alpha']);
  });

  test(
    'authoritative catalog snapshots repaint without manual refresh',
    () async {
      final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha');
      final beta = testSkill(slotKey: 'beta', displayName: 'Beta');
      final repository = FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
        documents: {'alpha': '# Alpha', 'beta': '# Beta'},
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final viewModel = container.read(skillBrowserViewModelProvider.notifier);
      await viewModel.load();

      repository.publish(InstalledSkillCatalog(revision: 2, skills: [beta]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.revision, 2);
      expect(viewModel.skills.single.slotKey, 'beta');
      expect(viewModel.selectedSkill?.slotKey, 'beta');
      expect(viewModel.document, '# Beta');
      expect(repository.refreshCalls, 0);
    },
  );

  test('workspace-authoritative refresh does not read the derived catalog provider', () async {
    final skillId = WorkspaceSkillId('managed-alpha');
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _workspaceSnapshot(
        revision: 1,
        skillId: skillId,
        slotKey: 'alpha',
      ),
      documents: const {'alpha': '# Alpha'},
    );
    final container = ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        skillBrowserRepositoryProvider.overrideWithValue(
          WorkspaceSkillBrowserRepository(workspace),
        ),
        skillBrowserCatalogAuthorityProvider.overrideWithValue(
          SkillBrowserCatalogAuthority.workspaceSnapshot,
        ),
        desktopSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    // Build the same derived provider that the production Installed page
    // watches before invoking the ViewModel command.
    expect(
      container.read(skillBrowserCatalogProvider).status,
      CatalogStatus.loading,
    );
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);
    await viewModel.load();
    await _settle();

    await viewModel.refresh();

    expect(workspace.refreshCalls, 1);
    expect(
      container.read(skillBrowserCatalogProvider).status,
      CatalogStatus.ready,
    );
  });

  test('root Snapshot listener keeps selection by managed ID through slot migration', () async {
    final skillId = WorkspaceSkillId('managed-alpha');
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _workspaceSnapshot(
        revision: 1,
        skillId: skillId,
        slotKey: 'alpha',
      ),
      documents: const {'alpha': '# Alpha'},
    );
    final container = ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        skillBrowserRepositoryProvider.overrideWithValue(
          WorkspaceSkillBrowserRepository(workspace),
        ),
        desktopSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      skillBrowserViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    await viewModel.load();
    await _settle();
    expect(workspace.openCalls, 1);
    expect(viewModel.selectedSkill?.id, skillId);
    expect(viewModel.selectedSkill?.slotKey, 'alpha');

    workspace.publish(
      _workspaceSnapshot(
        revision: 2,
        skillId: skillId,
        slotKey: 'renamed-alpha',
      ),
    );
    await pumpEventQueue();

    expect(viewModel.selectedSkill?.id, skillId);
    expect(viewModel.selectedSkill?.slotKey, 'renamed-alpha');
    final catalog = container.read(skillBrowserCatalogProvider);
    expect(catalog.revision, 2);
    expect(catalog.skills.single.slotKey, 'renamed-alpha');
  });

  test('unsupported platform does not open the Repository', () async {
    final repository = FakeSkillBrowserRepository();
    final container = _container(repository, desktopSupported: false);
    addTearDown(container.dispose);
    final viewModel = container.read(skillBrowserViewModelProvider.notifier);

    await viewModel.load();

    expect(viewModel.catalogStatus, CatalogStatus.unsupported);
    expect(repository.openCalls, 0);
  });
}

SkillsWorkspaceSnapshot _workspaceSnapshot({
  required int revision,
  required WorkspaceSkillId skillId,
  required String slotKey,
}) => SkillsWorkspaceSnapshot(
  revision: revision,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: skillId,
      slotKey: slotKey,
      declaredName: slotKey,
      displayName: 'Alpha',
      description: 'Alpha description',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime(2026),
        resolvedSourceRevision: 'local',
      ),
      activations: const [],
    ),
  ],
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

ProviderContainer _container(
  FakeSkillBrowserRepository repository, {
  bool desktopSupported = true,
}) {
  return ProviderContainer(
    overrides: [
      skillBrowserRepositoryProvider.overrideWithValue(repository),
      skillBrowserCatalogAuthorityProvider.overrideWithValue(
        SkillBrowserCatalogAuthority.repository,
      ),
      desktopSupportedProvider.overrideWithValue(desktopSupported),
    ],
  );
}
