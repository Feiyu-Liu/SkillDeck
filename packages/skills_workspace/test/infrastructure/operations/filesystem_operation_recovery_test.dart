import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_coordinator.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/lock_wait_policy.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/platform/operations/filesystem_operation_recovery.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_draft_snapshot.dart';
import 'package:skills_workspace/src/platform/filesystem/posix_filesystem_primitives.dart';
import 'package:test/test.dart';

import '../../support/process/direct_dart_process.dart';

const _operationId = '123e4567-e89b-42d3-a456-426614174310';
const _skillId = '123e4567-e89b-42d3-b456-426614174311';
const _subjectId = '123e4567-e89b-42d3-8456-426614174312';

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late PlatformDurableWorkspaceFilesystem filesystem;
  late OperationRecoverySpecRegistry registry;
  late _BackupMaintenance backup;
  late FilesystemOperationRecovery recovery;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'filesystem-operation-recovery-',
    );
    layout = WorkspaceLayout(path.join(temporary.path, 'workspace'));
    filesystem = PlatformDurableWorkspaceFilesystem();
    registry = OperationRecoverySpecRegistry();
    backup = _BackupMaintenance();
    recovery = FilesystemOperationRecovery(
      layout: layout,
      filesystem: filesystem,
      registry: registry,
      backupMaintenance: backup,
    );
  });

  tearDown(() async {
    if (!await temporary.exists()) return;
    await for (final entity in temporary.list(followLinks: false)) {
      await filesystem.removeOwnedPath(
        targetPath: entity.path,
        ownerRoot: temporary.path,
      );
    }
    await temporary.delete();
  });

  for (final link in [false, true]) {
    for (final scenario in ['changed', 'rollback', 'restart', 'cancel']) {
      test('inert adoption before image: link=$link $scenario', () async {
        final fixture = await _pathFixture(
          layout,
          registry,
          inertTarget: true,
          inertLink: link,
          verifyBeforeCapture: scenario == 'changed'
              ? (target) async {
                  // Simulate an external write after the preflight verifier has
                  // accepted its fingerprint, immediately before image capture.
                  if (link) {
                    await File(
                      path.join(path.dirname(target), 'missing'),
                    ).writeAsString('external');
                  } else {
                    await File(
                      path.join(target, 'external'),
                    ).writeAsString('external');
                  }
                  return true;
                }
              : null,
        );
        if (scenario == 'changed') {
          await expectLater(
            recovery.prepareStep(
              fixture.plan.preparationSteps.single,
              CancellationToken.none(),
            ),
            throwsA(isA<ExternalOperationPreconditionChanged>()),
          );
          expect(
            await File(
              path.join(
                link ? path.dirname(fixture.targetPath) : fixture.targetPath,
                link ? 'missing' : 'external',
              ),
            ).readAsString(),
            'external',
          );
          if (link) expect(await Link(fixture.targetPath).target(), 'missing');
          expect(
            await File(path.join(fixture.targetPath, 'SKILL.md')).exists(),
            isFalse,
          );
          return;
        }
        await recovery.prepareStep(
          fixture.plan.preparationSteps.single,
          CancellationToken.none(),
        );
        if (scenario == 'cancel') {
          final cancellation = CancellationSource();
          await cancellation.cancel();
          await expectLater(
            recovery.applyStep(
              fixture.plan.applyingSteps.single,
              cancellation.token,
            ),
            throwsA(anything),
          );
        } else {
          await recovery.applyStep(
            fixture.plan.applyingSteps.single,
            CancellationToken.none(),
          );
          expect(await _skillText(fixture.targetPath), 'new');
        }
        final rollbackRecovery = scenario == 'restart'
            ? FilesystemOperationRecovery(
                layout: layout,
                filesystem: filesystem,
                registry: OperationRecoverySpecRegistry(),
              )
            : recovery;
        await rollbackRecovery.rollback(
          fixture.plan,
          observedPhase: OperationJournalPhase.applying,
        );
        if (link) {
          expect(await Link(fixture.targetPath).target(), 'missing');
          expect(
            await FileSystemEntity.type(
              path.join(path.dirname(fixture.targetPath), 'missing'),
            ),
            FileSystemEntityType.notFound,
          );
        } else {
          expect(await Directory(fixture.targetPath).list().toList(), isEmpty);
        }
      }, skip: link && Platform.isWindows);
    }
  }

  test(
    'apply, pre-commit rollback, and repeated rollback are idempotent',
    () async {
      final fixture = await _pathFixture(layout, registry);

      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      expect(
        await Directory(
          layout.operationRecoveryPath(fixture.plan.operationId),
        ).exists(),
        isTrue,
      );

      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );
      expect(await _skillText(fixture.targetPath), 'new');

      await recovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );
      await recovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(await _skillText(fixture.targetPath), 'old');
      expect(await _knownResidues(fixture.targetPath), isEmpty);
    },
  );

  test(
    'capture and pre-commit rollback restore contained links verbatim',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Symbolic links need POSIX semantics.');
        return;
      }
      final fixture = await _pathFixture(layout, registry, linksInTarget: true);
      final fileLink = path.join(fixture.targetPath, 'CLAUDE.md');
      final directoryLink = path.join(fixture.targetPath, 'docs-link');

      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      final payload = operationRecoveryPayloadPath(
        bundleRoot: layout.operationRecoveryPath(fixture.plan.operationId),
        entryId: 'main',
        intended: false,
      );
      expect(await File(path.join(payload, 'AGENTS.md')).exists(), isTrue);
      expect(
        await FileSystemEntity.type(
          path.join(payload, 'CLAUDE.md'),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );

      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );
      expect(await _skillText(fixture.targetPath), 'new');
      expect(
        await FileSystemEntity.type(fileLink, followLinks: false),
        FileSystemEntityType.notFound,
      );

      await recovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );
      await recovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(await _skillText(fixture.targetPath), 'old');
      expect(
        await FileSystemEntity.type(fileLink, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await Link(fileLink).target(), 'AGENTS.md');
      expect(
        await FileSystemEntity.type(directoryLink, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await Link(directoryLink).target(), 'docs');
      expect(
        await File(
          path.join(fixture.targetPath, 'docs', 'guide.md'),
        ).readAsString(),
        'guide',
      );
      expect(await _knownResidues(fixture.targetPath), isEmpty);
    },
  );

  test(
    'NFD file names survive capture, reload, and rollback byte-exactly',
    () async {
      final fixture = await _pathFixture(
        layout,
        registry,
        nfdFileInTarget: true,
      );

      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      final manifestBytes = await File(
        path.join(
          layout.operationRecoveryPath(fixture.plan.operationId),
          'manifest.json',
        ),
      ).readAsBytes();
      expect(manifestBytes.every((byte) => byte < 0x80), isTrue);

      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );
      expect(await _skillText(fixture.targetPath), 'new');

      // A fresh adapter reads the bundle back from disk instead of memory.
      final reopened = FilesystemOperationRecovery(
        layout: layout,
        filesystem: filesystem,
        registry: registry,
        backupMaintenance: backup,
      );
      await reopened.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(await _skillText(fixture.targetPath), 'old');
      final names = await Directory(fixture.targetPath)
          .list(followLinks: false)
          .map((entity) => path.basename(entity.path))
          .toList();
      expect(names, contains(_nfdFileName));
      expect(names, isNot(contains(_nfcFileName)));
      expect(
        await File(path.join(fixture.targetPath, _nfdFileName)).readAsString(),
        'nfd',
      );
    },
  );

  test(
    'pre-commit rollback restores a before image with Git metadata',
    () async {
      final fixture = await _pathFixture(
        layout,
        registry,
        gitMetadataInTarget: true,
      );
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );
      expect(
        await File(path.join(fixture.targetPath, '.git', 'config')).exists(),
        isFalse,
      );

      await recovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(await _skillText(fixture.targetPath), 'old');
      expect(
        await File(
          path.join(fixture.targetPath, '.git', 'config'),
        ).readAsString(),
        'git',
      );
    },
  );

  test(
    'an intended plain materialization containing a link is rejected',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Symbolic links need POSIX semantics.');
        return;
      }
      final fixture = await _pathFixture(
        layout,
        registry,
        linkInIntended: true,
      );

      await expectLater(
        recovery.prepareStep(
          fixture.plan.preparationSteps.single,
          CancellationToken.none(),
        ),
        throwsA(_reason(OperationRecoveryFailureReason.entryTypeChanged)),
      );
      expect(await _skillText(fixture.targetPath), 'old');
      expect(
        await Directory(
          layout.operationRecoveryPath(fixture.plan.operationId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'a contained link repointed after capture is rejected, not overwritten',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Symbolic links need POSIX semantics.');
        return;
      }
      final fixture = await _pathFixture(layout, registry, linksInTarget: true);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      final fileLink = Link(path.join(fixture.targetPath, 'CLAUDE.md'));
      await fileLink.delete();
      await fileLink.create('SKILL.md');

      await expectLater(
        recovery.applyStep(
          fixture.plan.applyingSteps.single,
          CancellationToken.none(),
        ),
        throwsA(_reason(OperationRecoveryFailureReason.entryTypeChanged)),
      );
      expect(await _skillText(fixture.targetPath), 'old');
      expect(await fileLink.target(), 'SKILL.md');
    },
  );

  test('a schema 2 bundle left by an older build still rolls back', () async {
    final fixture = await _pathFixture(layout, registry);
    await recovery.prepareStep(
      fixture.plan.preparationSteps.single,
      CancellationToken.none(),
    );
    await recovery.applyStep(
      fixture.plan.applyingSteps.single,
      CancellationToken.none(),
    );
    expect(await _skillText(fixture.targetPath), 'new');
    await _downgradeBundleToSchema2(
      layout.operationRecoveryPath(fixture.plan.operationId),
    );

    final reopened = FilesystemOperationRecovery(
      layout: layout,
      filesystem: filesystem,
      registry: registry,
      backupMaintenance: backup,
    );
    await reopened.rollback(
      fixture.plan,
      observedPhase: OperationJournalPhase.applying,
    );

    expect(await _skillText(fixture.targetPath), 'old');
    expect(await _knownResidues(fixture.targetPath), isEmpty);
  });

  test(
    'repeated apply seals an already matching POSIX target read-only',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('POSIX permission modes are unavailable on Windows.');
        return;
      }
      final fixture = await _pathFixture(layout, registry);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );
      const primitives = PosixFilesystemPrimitives();
      await primitives.applyPosixMode(fixture.targetPath, 0x1ed);
      await primitives.applyPosixMode(
        path.join(fixture.targetPath, 'SKILL.md'),
        0x1a4,
      );

      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );

      expect((await Directory(fixture.targetPath).stat()).mode & 0x1ff, 0x16d);
      expect(
        (await File(path.join(fixture.targetPath, 'SKILL.md')).stat()).mode &
            0x1ff,
        0x124,
      );
    },
  );

  test(
    'pre-commit rollback removes canonical materialization and restores a legacy occurrence through its physical parent',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('This fixture requires a directory symbolic link.');
        return;
      }
      final operationId = OperationId(_operationId);
      final canonicalParent = Directory(
        path.join(temporary.path, 'canonical', 'skills'),
      );
      final physicalLegacyParent = Directory(
        path.join(temporary.path, 'physical', 'legacy-skills'),
      );
      final logicalLegacyParent = path.join(temporary.path, 'legacy-skills');
      await canonicalParent.create(recursive: true);
      await physicalLegacyParent.create(recursive: true);
      try {
        await Link(logicalLegacyParent).create(physicalLegacyParent.path);
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable at this location.');
        return;
      }

      final canonicalTarget = path.join(canonicalParent.path, 'reviewer');
      final legacyLogicalTarget = path.join(logicalLegacyParent, 'reviewer');
      final legacyPhysicalTarget = path.join(
        physicalLegacyParent.path,
        'reviewer',
      );
      final intended = path.join(
        layout.operationStagingPath(operationId),
        'canonical-materialization',
      );
      await Directory(legacyPhysicalTarget).create();
      await File(
        path.join(legacyPhysicalTarget, 'SKILL.md'),
      ).writeAsString('legacy');
      await Directory(intended).create(recursive: true);
      await File(path.join(intended, 'SKILL.md')).writeAsString('canonical');

      final prepare = operationRecoveryReference(operationId, 'evidence');
      final applyCanonical = operationRecoveryReference(
        operationId,
        'apply-canonical',
      );
      final retireLegacy = operationRecoveryReference(
        operationId,
        'retire-legacy',
      );
      registry.register(
        OperationRecoveryBundleSpec(
          context: OperationRecoveryContext(
            operationId: operationId,
            expectedRepositoryRevision: RepositoryRevision(0),
            committedRepositoryRevision: RepositoryRevision(1),
            destructive: false,
          ),
          entries: <OperationRecoveryEntrySpec>[
            OperationRecoveryEntrySpec(
              entryId: 'canonical',
              targetPath: canonicalTarget,
              intendedSourcePath: intended,
              intendedKind: OperationRecoveryEntryKind.directory,
            ),
            OperationRecoveryEntrySpec(
              entryId: 'legacy',
              targetPath: legacyLogicalTarget,
              intendedSourcePath: null,
              intendedKind: null,
              makeReadOnly: false,
              requirePlainDirectory: false,
            ),
          ],
          bindings: <OperationRecoveryStepBinding>[
            OperationRecoveryStepBinding(
              reference: prepare,
              action: OperationRecoveryAction.prepareEvidence,
            ),
            OperationRecoveryStepBinding(
              reference: applyCanonical,
              action: OperationRecoveryAction.applyEntry,
              entryId: 'canonical',
            ),
            OperationRecoveryStepBinding(
              reference: retireLegacy,
              action: OperationRecoveryAction.applyEntry,
              entryId: 'legacy',
            ),
          ],
        ),
      );
      final plan = _plan(
        operationId: operationId,
        preparationSteps: <PreparationOperationStep>[
          PreparationOperationStep(
            stepId: 'prepare-evidence',
            recoveryReference: prepare,
            kind: PreparationStepKind.recoveryEvidence,
          ),
        ],
        applyingSteps: <ApplyingOperationStep>[
          ApplyingOperationStep(
            stepId: 'apply-canonical',
            recoveryReference: applyCanonical,
            kind: ApplyingStepKind.materializationReplacement,
          ),
          ApplyingOperationStep(
            stepId: 'retire-legacy',
            recoveryReference: retireLegacy,
            kind: ApplyingStepKind.materializationReplacement,
          ),
        ],
        finalizationSteps: const <FinalizationOperationStep>[],
        destructive: false,
      );

      await recovery.prepareStep(
        plan.preparationSteps.single,
        CancellationToken.none(),
      );
      for (final step in plan.applyingSteps) {
        await recovery.applyStep(step, CancellationToken.none());
      }
      expect(await _skillText(canonicalTarget), 'canonical');
      expect(await Directory(legacyPhysicalTarget).exists(), isFalse);

      await recovery.rollback(
        plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(await Directory(canonicalTarget).exists(), isFalse);
      expect(await _skillText(legacyLogicalTarget), 'legacy');
      expect(await _skillText(legacyPhysicalTarget), 'legacy');
      expect(
        await FileSystemEntity.type(logicalLegacyParent, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );

  test(
    'roll-forward re-establishes intended bytes and is repeatable',
    () async {
      final fixture = await _pathFixture(layout, registry);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );

      // Simulate a pre-finalization external drift back to the former bytes.
      await filesystem.removeOwnedPath(
        targetPath: fixture.targetPath,
        ownerRoot: path.dirname(fixture.targetPath),
      );
      await Directory(fixture.targetPath).create();
      await File(
        path.join(fixture.targetPath, 'SKILL.md'),
      ).writeAsString('old');

      await recovery.rollForward(fixture.plan);
      await recovery.rollForward(fixture.plan);

      expect(await _skillText(fixture.targetPath), 'new');
      expect(await _knownResidues(fixture.targetPath), isEmpty);
    },
  );

  test(
    'Completed cleanup retains outcome and removes only recovery residue',
    () async {
      final fixture = await _pathFixture(layout, registry);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      await recovery.applyStep(
        fixture.plan.applyingSteps.single,
        CancellationToken.none(),
      );
      for (final step in fixture.plan.finalizationSteps) {
        await recovery.finalizeStep(step);
      }

      await recovery.cleanupCompleted(fixture.plan);
      await recovery.cleanupCompleted(fixture.plan);

      expect(await _skillText(fixture.targetPath), 'new');
      expect(
        await Directory(
          layout.operationRecoveryPath(fixture.plan.operationId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'Completed cleanup removes staging even when the bundle is absent',
    () async {
      final operationId = OperationId(_operationId);
      final staging = layout.operationStagingPath(operationId);
      await Directory(staging).create(recursive: true);
      await File(path.join(staging, 'candidate')).writeAsString('private');
      final plan = _plan(
        operationId: operationId,
        preparationSteps: const [],
        applyingSteps: const [],
        finalizationSteps: const [],
        destructive: false,
      );

      await recovery.cleanupCompleted(plan);
      await recovery.cleanupCompleted(plan);

      expect(await Directory(staging).exists(), isFalse);
    },
  );

  group('Draft compare-and-delete finalization', () {
    test(
      'unchanged captured Draft snapshot is deleted and yields DB effect',
      () async {
        final fixture = await _draftCleanupFixture(
          layout,
          filesystem,
          registry,
        );
        await recovery.prepareStep(
          fixture.plan.preparationSteps.single,
          CancellationToken.none(),
        );

        final effect = await recovery.finalizeStep(
          fixture.plan.finalizationSteps.single,
        );

        expect(await Directory(fixture.draftPath).exists(), isFalse);
        expect(effect, isA<DeleteReanchoredDraftEffect>());
        final deletion = effect! as DeleteReanchoredDraftEffect;
        expect(deletion.managedSkillId, ManagedSkillId(_skillId));
        expect(deletion.expectedBaseObjectId, fixture.expectedBase);
      },
    );

    test(
      'Windows executable intent remains stable during Draft cleanup',
      () async {
        final fixture = await _draftCleanupFixture(
          layout,
          filesystem,
          registry,
          simulateWindowsExecutableIntent: true,
        );
        final windowsRecovery = FilesystemOperationRecovery(
          layout: layout,
          filesystem: filesystem,
          registry: registry,
          backupMaintenance: backup,
          capturePosixExecutableIntent: false,
        );
        await windowsRecovery.prepareStep(
          fixture.plan.preparationSteps.single,
          CancellationToken.none(),
        );

        final effect = await windowsRecovery.finalizeStep(
          fixture.plan.finalizationSteps.single,
        );

        expect(await Directory(fixture.draftPath).exists(), isFalse);
        expect(effect, isA<DeleteReanchoredDraftEffect>());
      },
    );

    test(
      'post-capture save preserves live bytes and yields no DB effect',
      () async {
        final fixture = await _draftCleanupFixture(
          layout,
          filesystem,
          registry,
        );
        await recovery.prepareStep(
          fixture.plan.preparationSteps.single,
          CancellationToken.none(),
        );
        await File(
          path.join(fixture.draftPath, 'SKILL.md'),
        ).writeAsString('later save', flush: true);

        final effect = await recovery.finalizeStep(
          fixture.plan.finalizationSteps.single,
        );
        final replayed = await recovery.rollForward(fixture.plan);

        expect(effect, isNull);
        expect(replayed, isEmpty);
        expect(await _skillText(fixture.draftPath), 'later save');
      },
    );

    test(
      'save through old open fd after delete decision becomes durable preserve',
      () async {
        final fixture = await _draftCleanupFixture(
          layout,
          filesystem,
          registry,
        );
        await recovery.prepareStep(
          fixture.plan.preparationSteps.single,
          CancellationToken.none(),
        );
        final openHandle = await File(
          path.join(fixture.draftPath, 'SKILL.md'),
        ).open(mode: FileMode.append);
        final racingRecovery = FilesystemOperationRecovery(
          layout: layout,
          filesystem: filesystem,
          registry: registry,
          backupMaintenance: backup,
          onDraftCleanupFinalization: (event, target, quarantine) async {
            expect(
              event,
              DraftCleanupFinalizationEvent.deleteDecisionPersisted,
            );
            expect(await Directory(target).exists(), isFalse);
            expect(await Directory(quarantine).exists(), isTrue);
            await openHandle.writeString('-through-open-fd');
            await openHandle.flush();
          },
        );
        try {
          final effect = await racingRecovery.finalizeStep(
            fixture.plan.finalizationSteps.single,
          );
          expect(effect, isNull);
        } finally {
          await openHandle.close();
        }

        final restarted = FilesystemOperationRecovery(
          layout: layout,
          filesystem: filesystem,
          registry: OperationRecoverySpecRegistry(),
          backupMaintenance: backup,
        );
        final replayed = await restarted.rollForward(fixture.plan);

        expect(replayed, isEmpty);
        expect(await _skillText(fixture.draftPath), 'captured-through-open-fd');
      },
      skip: Platform.isWindows
          ? 'Windows does not permit quarantining a directory with an open file.'
          : false,
    );
  });

  test(
    'Prepared missing evidence is safe but Applying missing evidence fails',
    () async {
      final fixture = await _pathFixture(layout, registry);

      await recovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.prepared,
      );
      expect(await _skillText(fixture.targetPath), 'old');

      await expectLater(
        recovery.rollback(
          fixture.plan,
          observedPhase: OperationJournalPhase.applying,
        ),
        throwsA(_reason(OperationRecoveryFailureReason.bundleMissing)),
      );
    },
  );

  test(
    'unsealed Prepared envelope rollback cleans only private candidate evidence',
    () async {
      final fixture = await _pathFixture(layout, registry);
      final envelope = _preparedEnvelope(fixture.plan);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );

      await recovery.rollbackPreparedEnvelope(
        envelope,
        observedPhase: OperationJournalPhase.prepared,
      );
      await recovery.rollbackPreparedEnvelope(
        envelope,
        observedPhase: OperationJournalPhase.prepared,
      );

      expect(await _skillText(fixture.targetPath), 'old');
      expect(
        await Directory(
          layout.operationStagingPath(envelope.operationId),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          layout.operationRecoveryPath(envelope.operationId),
        ).exists(),
        isTrue,
      );

      await recovery.cleanupCompletedPreparedEnvelope(envelope);
      await recovery.cleanupCompletedPreparedEnvelope(envelope);
      expect(
        await Directory(
          layout.operationRecoveryPath(envelope.operationId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'unsealed crash before bundle publication still cleans owned staging',
    () async {
      final operationId = OperationId(_operationId);
      final staging = layout.operationStagingPath(operationId);
      await Directory(staging).create(recursive: true);
      await File(path.join(staging, 'candidate')).writeAsString('private');
      final envelope = PreparedOperationEnvelope(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(0),
        committedRepositoryRevision: RepositoryRevision(1),
        operationGeneration: 1,
        preparationSteps: [
          PreparationOperationStep(
            stepId: 'candidate',
            recoveryReference: operationRecoveryReference(
              operationId,
              'candidate',
            ),
            kind: PreparationStepKind.revisionCandidate,
          ),
        ],
        record: OperationRecordPlan(
          operationId: operationId,
          kind: 'test',
          retainWithoutSubjects: true,
          subjects: const [],
        ),
      );

      await recovery.rollbackPreparedEnvelope(
        envelope,
        observedPhase: OperationJournalPhase.prepared,
      );
      await recovery.rollbackPreparedEnvelope(
        envelope,
        observedPhase: OperationJournalPhase.prepared,
      );
      await recovery.cleanupCompletedPreparedEnvelope(envelope);
      await recovery.cleanupCompletedPreparedEnvelope(envelope);

      expect(await Directory(staging).exists(), isFalse);
    },
  );

  test(
    'startup recovers an unsealed Journal through concrete envelope recovery',
    () async {
      final fixture = await _pathFixture(layout, registry);
      final envelope = _preparedEnvelope(fixture.plan);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      final controlPlane = _PreparedRecoveryControlPlane(envelope);
      final coordinator = OperationCoordinator(
        writerLock: _ImmediateWriterLock(),
        controlPlane: controlPlane,
        recovery: recovery,
        referenceMaintenance: _NoopRevisionReferenceMaintenance(),
      );

      final report = await coordinator.recover();

      expect(
        report.operations.single.disposition,
        RecoveredOperationDisposition.rolledBack,
      );
      expect(controlPlane.rollbackCompleted, isTrue);
      expect(controlPlane.deleted, isTrue);
      expect(await _skillText(fixture.targetPath), 'old');
      expect(
        await Directory(
          layout.operationStagingPath(envelope.operationId),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          layout.operationRecoveryPath(envelope.operationId),
        ).exists(),
        isFalse,
      );
    },
  );

  test('untrusted envelope reference fails closed before cleanup', () async {
    final operationId = OperationId(_operationId);
    final staging = layout.operationStagingPath(operationId);
    await Directory(staging).create(recursive: true);
    final envelope = PreparedOperationEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: RepositoryRevision(0),
      committedRepositoryRevision: RepositoryRevision(1),
      operationGeneration: 1,
      preparationSteps: [
        PreparationOperationStep(
          stepId: 'candidate',
          recoveryReference: RecoveryReference('not-an-operation-reference'),
          kind: PreparationStepKind.revisionCandidate,
        ),
      ],
      record: OperationRecordPlan(
        operationId: operationId,
        kind: 'test',
        retainWithoutSubjects: true,
        subjects: const [],
      ),
    );

    await expectLater(
      recovery.rollbackPreparedEnvelope(
        envelope,
        observedPhase: OperationJournalPhase.prepared,
      ),
      throwsA(_reason(OperationRecoveryFailureReason.invalidReference)),
    );
    expect(await Directory(staging).exists(), isTrue);
  });

  test(
    'tampered bundle content fails closed without mutating target',
    () async {
      final fixture = await _pathFixture(layout, registry);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      final payload = path.join(
        layout.operationRecoveryPath(fixture.plan.operationId),
        'payloads',
        'main',
        'intended',
        'SKILL.md',
      );
      await File(payload).writeAsString('tampered', flush: true);

      await expectLater(
        recovery.applyStep(
          fixture.plan.applyingSteps.single,
          CancellationToken.none(),
        ),
        throwsA(_reason(OperationRecoveryFailureReason.checksumMismatch)),
      );

      expect(await _skillText(fixture.targetPath), 'old');
    },
  );

  test(
    'unexpected bundle payload fails closed without mutating target',
    () async {
      final fixture = await _pathFixture(layout, registry);
      await recovery.prepareStep(
        fixture.plan.preparationSteps.single,
        CancellationToken.none(),
      );
      final extraPayload = path.join(
        layout.operationRecoveryPath(fixture.plan.operationId),
        'payloads',
        'main',
        'intended',
        'EXTRA.md',
      );
      await File(extraPayload).writeAsString('unlisted', flush: true);

      await expectLater(
        recovery.applyStep(
          fixture.plan.applyingSteps.single,
          CancellationToken.none(),
        ),
        throwsA(_reason(OperationRecoveryFailureReason.checksumMismatch)),
      );

      expect(await _skillText(fixture.targetPath), 'old');
    },
  );

  test(
    'SQLite-only backup finalization retries while evidence stays durable',
    () async {
      final operationId = OperationId(_operationId);
      final steps = OperationRecoveryPlanFactory(registry: registry)
          .createSqliteOnly(
            operationId: operationId,
            expectedRepositoryRevision: RepositoryRevision(0),
            committedRepositoryRevision: RepositoryRevision(1),
            destructive: false,
          );
      final plan = _plan(
        operationId: operationId,
        preparationSteps: steps.preparationSteps,
        applyingSteps: steps.applyingSteps,
        finalizationSteps: steps.finalizationSteps,
        destructive: false,
      );
      await Directory(
        layout.operationStagingPath(operationId),
      ).create(recursive: true);
      await recovery.prepareStep(
        steps.preparationSteps.single,
        CancellationToken.none(),
      );
      backup.failNext = true;

      await expectLater(
        recovery.finalizeStep(steps.finalizationSteps.first),
        throwsStateError,
      );
      expect(
        await Directory(layout.operationRecoveryPath(operationId)).exists(),
        isTrue,
      );
      await recovery.finalizeStep(steps.finalizationSteps.first);
      await recovery.finalizeStep(steps.finalizationSteps[1]);
      await recovery.finalizeStep(steps.finalizationSteps[2]);
      expect(
        await Directory(layout.operationStagingPath(operationId)).exists(),
        isFalse,
      );

      await recovery.rollForward(plan);
      expect(backup.calls, 3);
      await recovery.cleanupCompleted(plan);
      expect(
        await Directory(layout.operationRecoveryPath(operationId)).exists(),
        isFalse,
      );
    },
  );

  for (final occupant in ['empty', 'link']) {
    test(
      'child-process crash restores auto-replaced $occupant',
      () async {
        final scenarioLayout = WorkspaceLayout(
          path.join(temporary.path, occupant, 'workspace'),
        );
        await _crashChildAt(
          workspaceRoot: scenarioLayout.rootPath,
          crashPoint: DurablePathMutationBarrier.afterVerification.name,
          occupant: occupant,
        );
        final freshRecovery = FilesystemOperationRecovery(
          layout: scenarioLayout,
          filesystem: PlatformDurableWorkspaceFilesystem(),
          registry: OperationRecoverySpecRegistry(),
        );
        await freshRecovery.rollback(
          _crashPlan(scenarioLayout),
          observedPhase: OperationJournalPhase.applying,
        );
        final target = path.join(
          scenarioLayout.repositoryCopiesRoot,
          'reviewer',
        );
        if (occupant == 'link') {
          expect(await Link(target).target(), 'missing');
        } else {
          expect(await Directory(target).list().toList(), isEmpty);
        }
      },
      skip: occupant == 'link' && Platform.isWindows,
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }

  for (final barrier in DurablePathMutationBarrier.values) {
    test('child-process crash at ${barrier.name} rolls back exactly', () async {
      final scenarioLayout = WorkspaceLayout(
        path.join(temporary.path, barrier.name, 'workspace'),
      );
      await _crashChildAt(
        workspaceRoot: scenarioLayout.rootPath,
        crashPoint: barrier.name,
      );
      final scenarioRecovery = FilesystemOperationRecovery(
        layout: scenarioLayout,
        filesystem: PlatformDurableWorkspaceFilesystem(),
        registry: OperationRecoverySpecRegistry(),
      );
      final plan = _crashPlan(scenarioLayout);

      await scenarioRecovery.rollback(
        plan,
        observedPhase: OperationJournalPhase.applying,
      );
      await scenarioRecovery.rollback(
        plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(
        await _skillText(
          path.join(scenarioLayout.repositoryCopiesRoot, 'reviewer'),
        ),
        'old',
        reason: barrier.name,
      );
    }, timeout: const Timeout(Duration(seconds: 45)));
  }

  test(
    'child-process crashes recover from Prepared and roll forward after BCP',
    () async {
      final preparedLayout = WorkspaceLayout(
        path.join(temporary.path, 'prepared', 'workspace'),
      );
      await _crashChildAt(
        workspaceRoot: preparedLayout.rootPath,
        crashPoint: 'prepared',
      );
      final preparedRecovery = FilesystemOperationRecovery(
        layout: preparedLayout,
        filesystem: PlatformDurableWorkspaceFilesystem(),
        registry: OperationRecoverySpecRegistry(),
      );
      await preparedRecovery.rollback(
        _crashPlan(preparedLayout),
        observedPhase: OperationJournalPhase.prepared,
      );
      expect(
        await _skillText(
          path.join(preparedLayout.repositoryCopiesRoot, 'reviewer'),
        ),
        'old',
      );

      for (final phase in ['committed', 'finalizing']) {
        final committedLayout = WorkspaceLayout(
          path.join(temporary.path, phase, 'workspace'),
        );
        await _crashChildAt(
          workspaceRoot: committedLayout.rootPath,
          crashPoint: DurablePathMutationBarrier.afterVerification.name,
        );
        final committedRecovery = FilesystemOperationRecovery(
          layout: committedLayout,
          filesystem: PlatformDurableWorkspaceFilesystem(),
          registry: OperationRecoverySpecRegistry(),
        );
        final plan = _crashPlan(committedLayout);
        await committedRecovery.rollForward(plan);
        await committedRecovery.rollForward(plan);
        expect(
          await _skillText(
            path.join(committedLayout.repositoryCopiesRoot, 'reviewer'),
          ),
          'new',
          reason: phase,
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'destructive execution arms before apply and releases before backup',
    () async {
      final events = <String>[];
      final destructive = _DestructiveMaintenance(events);
      final destructiveBackup = _BackupMaintenance(events);
      final destructiveRecovery = FilesystemOperationRecovery(
        layout: layout,
        filesystem: filesystem,
        registry: registry,
        backupMaintenance: destructiveBackup,
        destructiveMaintenance: destructive,
      );
      final fixture = _destructiveFixture(layout, registry);

      for (final step in fixture.plan.preparationSteps) {
        await destructiveRecovery.prepareStep(step, CancellationToken.none());
      }
      for (final step in fixture.plan.applyingSteps) {
        await destructiveRecovery.applyStep(step, CancellationToken.none());
      }
      for (final step in fixture.plan.finalizationSteps) {
        await destructiveRecovery.finalizeStep(step);
      }

      expect(events, [
        'backup.arm',
        'destructive.prepare',
        'destructive.verify',
        'backup.complete',
      ]);
      expect(
        await Directory(
          layout.operationRecoveryPath(fixture.plan.operationId),
        ).exists(),
        isTrue,
      );
      await destructiveRecovery.cleanupCompleted(fixture.plan);
      expect(
        await Directory(
          layout.operationRecoveryPath(fixture.plan.operationId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'destructive rollback restores steady fence only after resource rollback',
    () async {
      final events = <String>[];
      final destructiveRecovery = FilesystemOperationRecovery(
        layout: layout,
        filesystem: filesystem,
        registry: registry,
        backupMaintenance: _BackupMaintenance(events),
        destructiveMaintenance: _DestructiveMaintenance(events),
      );
      final fixture = _destructiveFixture(layout, registry);
      for (final step in fixture.plan.preparationSteps) {
        await destructiveRecovery.prepareStep(step, CancellationToken.none());
      }
      for (final step in fixture.plan.applyingSteps) {
        await destructiveRecovery.applyStep(step, CancellationToken.none());
      }
      events.clear();

      await destructiveRecovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );
      await destructiveRecovery.rollback(
        fixture.plan,
        observedPhase: OperationJournalPhase.applying,
      );

      expect(events, [
        'destructive.rollback',
        'backup.restore',
        'destructive.rollback',
        'backup.restore',
      ]);
    },
  );

  test(
    'destructive roll-forward is ordered and repeatable after BCP',
    () async {
      final events = <String>[];
      final destructiveRecovery = FilesystemOperationRecovery(
        layout: layout,
        filesystem: filesystem,
        registry: registry,
        backupMaintenance: _BackupMaintenance(events),
        destructiveMaintenance: _DestructiveMaintenance(events),
      );
      final fixture = _destructiveFixture(layout, registry);
      await destructiveRecovery.prepareStep(
        fixture.plan.preparationSteps.first,
        CancellationToken.none(),
      );
      events.clear();

      await destructiveRecovery.rollForward(fixture.plan);
      await destructiveRecovery.rollForward(fixture.plan);

      expect(events, [
        'destructive.rollForward',
        'destructive.verify',
        'backup.complete',
        'destructive.rollForward',
        'destructive.verify',
        'backup.complete',
      ]);
    },
  );

  for (final failurePoint in <String>[
    'backup.arm',
    'destructive.prepare',
    'destructive.verify',
    'backup.complete',
  ]) {
    test(
      '$failurePoint failure retries only the idempotent boundary',
      () async {
        final events = <String>[];
        final destructive = _DestructiveMaintenance(events);
        final destructiveBackup = _BackupMaintenance(events);
        final destructiveRecovery = FilesystemOperationRecovery(
          layout: layout,
          filesystem: filesystem,
          registry: registry,
          backupMaintenance: destructiveBackup,
          destructiveMaintenance: destructive,
        );
        final fixture = _destructiveFixture(layout, registry);
        final preparation = fixture.plan.preparationSteps;
        final applying = fixture.plan.applyingSteps;
        final finalization = fixture.plan.finalizationSteps;
        final barrier = preparation.singleWhere(
          (step) => step.kind == PreparationStepKind.destructiveBarrier,
        );
        final resources = preparation.singleWhere(
          (step) => step.kind == PreparationStepKind.destructiveResources,
        );
        final verifyIndex = finalization.indexWhere(
          (step) => step.stepId == 'recovery.verify-destructive-resources',
        );
        final backupIndex = finalization.indexWhere(
          (step) => step.kind == FinalizationStepKind.backupRotation,
        );
        expect(verifyIndex, isNonNegative);
        expect(backupIndex, greaterThan(verifyIndex));
        await destructiveRecovery.prepareStep(
          preparation.first,
          CancellationToken.none(),
        );

        late Future<void> Function() invokeFailurePoint;
        switch (failurePoint) {
          case 'backup.arm':
            destructiveBackup.failAt = failurePoint;
            invokeFailurePoint = () => destructiveRecovery.prepareStep(
              barrier,
              CancellationToken.none(),
            );
          case 'destructive.prepare':
            await destructiveRecovery.prepareStep(
              barrier,
              CancellationToken.none(),
            );
            destructive.failAt = failurePoint;
            invokeFailurePoint = () => destructiveRecovery.prepareStep(
              resources,
              CancellationToken.none(),
            );
          case 'destructive.verify':
            for (final step in preparation.skip(1)) {
              await destructiveRecovery.prepareStep(
                step,
                CancellationToken.none(),
              );
            }
            for (final step in applying) {
              await destructiveRecovery.applyStep(
                step,
                CancellationToken.none(),
              );
            }
            for (final step in finalization.take(verifyIndex)) {
              await destructiveRecovery.finalizeStep(step);
            }
            destructive.failAt = failurePoint;
            invokeFailurePoint = () =>
                destructiveRecovery.finalizeStep(finalization[verifyIndex]);
          case 'backup.complete':
            for (final step in preparation.skip(1)) {
              await destructiveRecovery.prepareStep(
                step,
                CancellationToken.none(),
              );
            }
            for (final step in applying) {
              await destructiveRecovery.applyStep(
                step,
                CancellationToken.none(),
              );
            }
            for (final step in finalization.take(backupIndex)) {
              await destructiveRecovery.finalizeStep(step);
            }
            destructiveBackup.failAt = failurePoint;
            invokeFailurePoint = () =>
                destructiveRecovery.finalizeStep(finalization[backupIndex]);
        }

        await expectLater(invokeFailurePoint(), throwsStateError);
        await invokeFailurePoint();
        expect(events.where((event) => event == failurePoint), hasLength(2));
      },
    );
  }
}

final class _NoopRevisionReferenceMaintenance
    implements OperationRevisionReferenceMaintenancePort {
  @override
  Future<void> reconcileRevisionReferences({
    Set<ManagedSkillId>? isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) async {}
}

Future<void> _crashChildAt({
  required String workspaceRoot,
  required String crashPoint,
  String? occupant,
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    directDartScriptArguments(
      'test/support/operations/filesystem_operation_recovery_crash_helper.dart',
      <String>[workspaceRoot, crashPoint, ?occupant],
    ),
    workingDirectory: Directory.current.path,
    environment: Platform.environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  final ready = Completer<void>();
  final stderr = StringBuffer();
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.contains('READY:$crashPoint') && !ready.isCompleted) {
          ready.complete();
        }
      });
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(stderr.write);
  try {
    await ready.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw StateError('Crash helper did not reach $crashPoint: $stderr'),
    );
    await PlatformGitProcessTreeTerminator.current().terminate(process.pid);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  } finally {
    if (!ready.isCompleted) {
      process.kill(ProcessSignal.sigkill);
    }
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}

OperationPlan _crashPlan(WorkspaceLayout layout) {
  final operationId = OperationId(_operationId);
  final prepareReference = operationRecoveryReference(operationId, 'evidence');
  final applyReference = operationRecoveryReference(operationId, 'apply-main');
  return _plan(
    operationId: operationId,
    preparationSteps: [
      PreparationOperationStep(
        stepId: 'prepare-evidence',
        recoveryReference: prepareReference,
        kind: PreparationStepKind.recoveryEvidence,
      ),
    ],
    applyingSteps: [
      ApplyingOperationStep(
        stepId: 'apply-main',
        recoveryReference: applyReference,
        kind: ApplyingStepKind.materializationReplacement,
      ),
    ],
    finalizationSteps: const [],
    destructive: false,
  );
}

/// A before image shaped like an adopted external Skill: a file link, a
/// directory link, and an NFD-named file. Links need POSIX semantics.
const _nfdFileName = 'café.md';
const _nfcFileName = 'café.md';

Future<_PathFixture> _pathFixture(
  WorkspaceLayout layout,
  OperationRecoverySpecRegistry registry, {
  bool linksInTarget = false,
  bool nfdFileInTarget = false,
  bool gitMetadataInTarget = false,
  bool linkInIntended = false,
  bool inertTarget = false,
  bool inertLink = false,
  OperationRecoveryPreCaptureVerifier? verifyBeforeCapture,
}) async {
  final operationId = OperationId(_operationId);
  final target = path.join(layout.repositoryCopiesRoot, 'reviewer');
  final intended = path.join(layout.operationStagingPath(operationId), 'main');
  await Directory(target).create(recursive: true);
  if (inertLink) {
    await Directory(target).delete();
    await Link(target).create('missing');
  } else if (!inertTarget) {
    await File(path.join(target, 'SKILL.md')).writeAsString('old');
  }
  if (linksInTarget) {
    await File(path.join(target, 'AGENTS.md')).writeAsString('agents');
    await Link(path.join(target, 'CLAUDE.md')).create('AGENTS.md');
    await Directory(path.join(target, 'docs')).create();
    await File(path.join(target, 'docs', 'guide.md')).writeAsString('guide');
    await Link(path.join(target, 'docs-link')).create('docs');
  }
  if (nfdFileInTarget) {
    await File(path.join(target, _nfdFileName)).writeAsString('nfd');
  }
  if (gitMetadataInTarget) {
    await Directory(path.join(target, '.git')).create();
    await File(path.join(target, '.git', 'config')).writeAsString('git');
  }
  await Directory(path.join(intended, 'scripts')).create(recursive: true);
  await File(path.join(intended, 'SKILL.md')).writeAsString('new');
  if (linkInIntended) {
    await Link(path.join(intended, 'CLAUDE.md')).create('SKILL.md');
  }
  await File(
    path.join(intended, 'scripts', 'run.sh'),
  ).writeAsString('#!/bin/sh');
  if (!Platform.isWindows) {
    await Process.run('chmod', [
      '755',
      path.join(intended, 'scripts', 'run.sh'),
    ]);
  }

  final prepareRef = operationRecoveryReference(operationId, 'evidence');
  final applyRef = operationRecoveryReference(operationId, 'apply-main');
  final verifyRef = operationRecoveryReference(operationId, 'verify-main');
  final cleanupRef = operationRecoveryReference(operationId, 'cleanup-main');
  registry.register(
    OperationRecoveryBundleSpec(
      context: OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(0),
        committedRepositoryRevision: RepositoryRevision(1),
        destructive: false,
      ),
      entries: [
        OperationRecoveryEntrySpec(
          requiresInertBeforeImage: inertTarget,
          verifyBeforeCapture: verifyBeforeCapture,
          entryId: 'main',
          targetPath: target,
          intendedSourcePath: intended,
          intendedKind: OperationRecoveryEntryKind.directory,
        ),
      ],
      bindings: [
        OperationRecoveryStepBinding(
          reference: prepareRef,
          action: OperationRecoveryAction.prepareEvidence,
        ),
        OperationRecoveryStepBinding(
          reference: applyRef,
          action: OperationRecoveryAction.applyEntry,
          entryId: 'main',
        ),
        OperationRecoveryStepBinding(
          reference: verifyRef,
          action: OperationRecoveryAction.verifyEntry,
          entryId: 'main',
        ),
        OperationRecoveryStepBinding(
          reference: cleanupRef,
          action: OperationRecoveryAction.cleanupEntryResidue,
          entryId: 'main',
        ),
      ],
    ),
  );
  final plan = _plan(
    operationId: operationId,
    preparationSteps: [
      PreparationOperationStep(
        stepId: 'prepare-evidence',
        recoveryReference: prepareRef,
        kind: PreparationStepKind.recoveryEvidence,
      ),
    ],
    applyingSteps: [
      ApplyingOperationStep(
        stepId: 'apply-main',
        recoveryReference: applyRef,
        kind: ApplyingStepKind.materializationReplacement,
      ),
    ],
    finalizationSteps: [
      FinalizationOperationStep(
        stepId: 'verify-main',
        recoveryReference: verifyRef,
        kind: FinalizationStepKind.materializationVerification,
      ),
      FinalizationOperationStep(
        stepId: 'cleanup-main',
        recoveryReference: cleanupRef,
        kind: FinalizationStepKind.stagingCleanup,
      ),
    ],
    destructive: false,
  );
  return _PathFixture(plan: plan, targetPath: target);
}

Future<_DraftCleanupFixture> _draftCleanupFixture(
  WorkspaceLayout layout,
  PlatformDurableWorkspaceFilesystem filesystem,
  OperationRecoverySpecRegistry registry, {
  bool simulateWindowsExecutableIntent = false,
}) async {
  final operationId = OperationId(_operationId);
  final draftPath = path.join(layout.draftsRoot, _skillId);
  await Directory(draftPath).create(recursive: true);
  await File(
    path.join(draftPath, 'SKILL.md'),
  ).writeAsString('captured', flush: true);
  if (simulateWindowsExecutableIntent) {
    await File(
      path.join(draftPath, 'existing.sh'),
    ).writeAsString('#!/bin/sh\n', flush: true);
  }
  final fingerprintResult =
      await FilesystemDraftSnapshotAdapter(filesystem: filesystem).fingerprint(
        DraftCaptureRequest(
          liveDraftPath: draftPath,
          stagingDestinationPath: path.join(
            layout.operationStagingPath(operationId),
            'unused-fingerprint',
          ),
          capturePosixExecutableIntent: !simulateWindowsExecutableIntent,
          executableIntentOverrides: simulateWindowsExecutableIntent
              ? const <String, bool>{'existing.sh': true}
              : const <String, bool>{},
        ),
      );
  final fingerprint = fingerprintResult.valueOrNull!;
  final prepareRef = operationRecoveryReference(operationId, 'evidence');
  final cleanupRef = operationRecoveryReference(operationId, 'draft-cleanup');
  final expectedBase = RevisionObjectId('e' * 40);
  registry.register(
    OperationRecoveryBundleSpec(
      context: OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(0),
        committedRepositoryRevision: RepositoryRevision(1),
        destructive: false,
      ),
      entries: const [],
      draftCleanups: <OperationRecoveryDraftCleanupSpec>[
        OperationRecoveryDraftCleanupSpec(
          cleanupId: 'draft-cleanup',
          managedSkillId: ManagedSkillId(_skillId),
          expectedBaseObjectId: expectedBase,
          targetPath: draftPath,
          capturedFingerprint: fingerprint,
        ),
      ],
      bindings: <OperationRecoveryStepBinding>[
        OperationRecoveryStepBinding(
          reference: prepareRef,
          action: OperationRecoveryAction.prepareEvidence,
        ),
        OperationRecoveryStepBinding(
          reference: cleanupRef,
          action: OperationRecoveryAction.finalizeDraftCleanup,
          entryId: 'draft-cleanup',
        ),
      ],
    ),
  );
  final plan = _plan(
    operationId: operationId,
    preparationSteps: <PreparationOperationStep>[
      PreparationOperationStep(
        stepId: 'prepare-evidence',
        recoveryReference: prepareRef,
        kind: PreparationStepKind.recoveryEvidence,
      ),
    ],
    applyingSteps: const <ApplyingOperationStep>[],
    finalizationSteps: <FinalizationOperationStep>[
      FinalizationOperationStep(
        stepId: 'draft-cleanup',
        recoveryReference: cleanupRef,
        kind: FinalizationStepKind.draftLifecycle,
      ),
    ],
    destructive: false,
  );
  return _DraftCleanupFixture(
    plan: plan,
    draftPath: draftPath,
    expectedBase: expectedBase,
  );
}

OperationPlan _plan({
  required OperationId operationId,
  required List<PreparationOperationStep> preparationSteps,
  required List<ApplyingOperationStep> applyingSteps,
  required List<FinalizationOperationStep> finalizationSteps,
  required bool destructive,
}) => OperationPlan(
  operationId: operationId,
  expectedRepositoryRevision: RepositoryRevision(0),
  committedRepositoryRevision: RepositoryRevision(1),
  operationGeneration: 1,
  preparationSteps: preparationSteps,
  applyingSteps: applyingSteps,
  finalizationSteps: finalizationSteps,
  revisionSelectionChanges: const [],
  businessChanges: WorkspaceBusinessChangeSet(
    incrementsDestructionEpoch: destructive,
  ),
  record: OperationRecordPlan(
    operationId: operationId,
    kind: 'test',
    retainWithoutSubjects: true,
    subjects: [
      OperationSubjectPlan(
        reference: OperationSubjectReference(
          operationId: operationId,
          subjectId: _subjectId,
        ),
        managedSkillId: ManagedSkillId(_skillId),
        displayName: 'Reviewer',
      ),
    ],
  ),
);

PreparedOperationEnvelope _preparedEnvelope(OperationPlan plan) =>
    PreparedOperationEnvelope(
      operationId: plan.operationId,
      expectedRepositoryRevision: plan.expectedRepositoryRevision,
      committedRepositoryRevision: plan.committedRepositoryRevision,
      operationGeneration: plan.operationGeneration,
      preparationSteps: [plan.preparationSteps.first],
      record: plan.record,
    );

_PathFixture _destructiveFixture(
  WorkspaceLayout layout,
  OperationRecoverySpecRegistry registry,
) {
  final operationId = OperationId(_operationId);
  registry.stageDestructiveEntries(operationId, <OperationRecoveryEntrySpec>[
    OperationRecoveryEntrySpec(
      entryId: 'destructive-0001-repository',
      targetPath: path.join(layout.repositoryCopiesRoot, 'reviewer'),
      intendedSourcePath: null,
      intendedKind: null,
      makeReadOnly: false,
      requirePlainDirectory: false,
    ),
  ]);
  final steps = OperationRecoveryPlanFactory(registry: registry)
      .createDestructive(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(0),
        committedRepositoryRevision: RepositoryRevision(1),
        intent: _destructiveIntent(),
      );
  return _PathFixture(
    plan: _plan(
      operationId: operationId,
      preparationSteps: steps.preparationSteps,
      applyingSteps: steps.applyingSteps,
      finalizationSteps: steps.finalizationSteps,
      destructive: true,
    ),
    targetPath: '',
  );
}

RemovalRecoveryIntent _destructiveIntent() => RemovalRecoveryIntent(
  skills: [
    DestructiveSkillRecoveryIntent(
      managedSkillId: ManagedSkillId(_skillId),
      slotKey: 'reviewer',
      sourceLineages: [
        RecoverySourceLineageIntent(
          sourceLineage: SourceLineageReference('lineage-1'),
        ),
      ],
      activationIds: const ['activation-1'],
      hasDraft: true,
      hasUpdateCandidateSession: true,
    ),
  ],
);

/// Rewrites a published schema-3 bundle in place as an older build would have
/// written it: schema 2, raw strings, and no `links` keys.
Future<void> _downgradeBundleToSchema2(String bundleRoot) async {
  Object? disarm(Object? value) => switch (value) {
    final String string => Uri.decodeComponent(string),
    final Map<String, Object?> map => <String, Object?>{
      for (final entry in map.entries)
        if (entry.key != 'links' || !map.containsKey('present'))
          entry.key: disarm(entry.value),
    },
    final List<Object?> list => list.map(disarm).toList(),
    _ => value,
  };
  final manifestFile = File(path.join(bundleRoot, 'manifest.json'));
  final armored =
      jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
  final legacy = disarm(armored)! as Map<String, Object?>..['schema'] = 2;
  final manifestBytes = canonicalJson.encode(legacy);
  await manifestFile.writeAsBytes(manifestBytes, flush: true);
  await File(path.join(bundleRoot, 'COMPLETE')).writeAsBytes(
    canonicalJson.encode({
      'schema': 2,
      'manifestSha256': sha256.convert(manifestBytes).toString(),
    }),
    flush: true,
  );
}

Future<String> _skillText(String root) =>
    File(path.join(root, 'SKILL.md')).readAsString();

Future<List<String>> _knownResidues(String targetPath) async {
  final parent = Directory(path.dirname(targetPath));
  if (!await parent.exists()) return const [];
  return parent
      .list(followLinks: false)
      .where((entity) => path.basename(entity.path).contains('skills-recovery'))
      .map((entity) => entity.path)
      .toList();
}

Matcher _reason(OperationRecoveryFailureReason reason) =>
    isA<OperationRecoveryException>().having(
      (error) => error.reason,
      'reason',
      reason,
    );

final class _PathFixture {
  const _PathFixture({required this.plan, required this.targetPath});

  final OperationPlan plan;
  final String targetPath;
}

final class _DraftCleanupFixture {
  const _DraftCleanupFixture({
    required this.plan,
    required this.draftPath,
    required this.expectedBase,
  });

  final OperationPlan plan;
  final String draftPath;
  final RevisionObjectId expectedBase;
}

final class _BackupMaintenance
    implements OperationRecoveryBackupMaintenancePort {
  _BackupMaintenance([List<String>? events]) : events = events ?? <String>[];

  int calls = 0;
  bool failNext = false;
  String? failAt;
  final List<String> events;

  @override
  Future<void> armDestructiveBarrier(OperationRecoveryContext context) =>
      _record('backup.arm');

  @override
  Future<void> completeCommittedDestruction(OperationRecoveryContext context) =>
      _record('backup.complete');

  @override
  Future<void> rotate(OperationRecoveryContext context) async {
    calls += 1;
    await _record('backup.rotate');
    if (failNext) {
      failNext = false;
      throw StateError('injected backup rotation failure');
    }
  }

  @override
  Future<void> restoreSteadyAfterProvenRollback(
    OperationRecoveryContext context,
  ) => _record('backup.restore');

  Future<void> _record(String event) async {
    events.add(event);
    if (failAt == event) {
      failAt = null;
      throw StateError('injected $event failure');
    }
  }
}

final class _DestructiveMaintenance
    implements OperationRecoveryDestructiveMaintenancePort {
  _DestructiveMaintenance(this.events);

  final List<String> events;
  String? failAt;

  @override
  Future<void> prepare(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
    CancellationToken cancellationToken,
  ) => _record('destructive.prepare');

  @override
  Future<void> rollback(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  ) => _record('destructive.rollback');

  @override
  Future<void> rollForward(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  ) => _record('destructive.rollForward');

  @override
  Future<void> verify(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  ) => _record('destructive.verify');

  Future<void> _record(String event) async {
    events.add(event);
    if (failAt == event) {
      failAt = null;
      throw StateError('injected $event failure');
    }
  }
}

final class _ImmediateWriterLock implements WorkspaceWriterLockPort {
  @override
  Future<WorkspaceWriterLease> acquire({LockWaitPolicy? waitPolicy}) async =>
      _ImmediateWriterLease();
}

final class _ImmediateWriterLease implements WorkspaceWriterLease {
  @override
  Future<void> release() async {}
}

final class _PreparedRecoveryControlPlane implements OperationControlPlanePort {
  _PreparedRecoveryControlPlane(this.envelope)
    : journal = JournaledOperation.prepared(
        envelope: envelope,
        phase: OperationJournalPhase.prepared,
      );

  final PreparedOperationEnvelope envelope;
  JournaledOperation journal;
  bool rollbackCompleted = false;
  bool deleted = false;

  @override
  Future<List<JournaledOperation>> loadRecoverableOperations() async =>
      deleted ? const [] : [journal];

  @override
  Future<void> completePreparedEnvelopeRollback(
    PreparedOperationEnvelope envelope,
    OperationAbortReason reason,
  ) async {
    if (!identical(envelope, this.envelope)) {
      throw StateError('unexpected envelope');
    }
    rollbackCompleted = true;
    journal = JournaledOperation.prepared(
      envelope: envelope,
      phase: OperationJournalPhase.completed,
    );
  }

  @override
  Future<void> deleteCompletedJournal(OperationId operationId) async {
    if (operationId != envelope.operationId || !rollbackCompleted) {
      throw StateError('unexpected cleanup');
    }
    deleted = true;
  }

  @override
  Future<void> commitBusinessState(OperationPlan plan) =>
      throw UnimplementedError();

  @override
  Future<void> applyFinalizationEffect(
    OperationId operationId,
    OperationFinalizationEffect effect,
  ) => throw UnimplementedError();

  @override
  Future<void> complete(OperationPlan plan) => throw UnimplementedError();

  @override
  Future<void> completeRollback(
    OperationPlan plan,
    OperationAbortReason reason,
  ) => throw UnimplementedError();

  @override
  Future<void> markApplying(OperationId operationId) =>
      throw UnimplementedError();

  @override
  Future<void> markFinalizing(OperationId operationId) =>
      throw UnimplementedError();

  @override
  Future<void> markStepCompleted(OperationId operationId, String stepId) =>
      throw UnimplementedError();

  @override
  Future<void> markStepStarted(OperationId operationId, String stepId) =>
      throw UnimplementedError();

  @override
  Future<void> persistPrepared(OperationPlan plan) =>
      throw UnimplementedError();

  @override
  Future<void> persistPreparedEnvelope(PreparedOperationEnvelope envelope) =>
      throw UnimplementedError();

  @override
  Future<RepositoryRevision> readRepositoryRevision() =>
      throw UnimplementedError();

  @override
  Future<void> sealPreparedPlan(
    PreparedOperationEnvelope envelope,
    OperationPlan plan,
  ) => throw UnimplementedError();
}
