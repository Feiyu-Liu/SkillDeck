import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';
import '../../support/operations/destructive_sqlite_crash_harness.dart';

void main() {
  for (final window in [
    'beforeCapture',
    'beforeDraftApply',
    'afterDraftDisplaced',
  ]) {
    for (final kind in [
      'directory',
      'file',
      'link',
      if (window != 'afterDraftDisplaced') 'inPlace',
    ]) {
      test(
        'guarded Removal preserves $kind at $window and restores other SQLite resources',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'guarded-removal-race-',
          );
          addTearDown(
            () => PlatformDurableWorkspaceFilesystem().removeOwnedPath(
              targetPath: temp.path,
              ownerRoot: temp.parent.path,
            ),
          );
          final outcome = await exerciseGuardedRemovalRace(
            workspaceRoot: temp.path,
            window: window,
            editKind: kind,
          );
          expect(
            outcome,
            anyOf(isA<OperationRolledBack>(), isA<OperationRejected>()),
          );
          final layout = WorkspaceLayout(temp.path),
              id = ManagedSkillId(destructiveCrashSkillId);
          final database = sqlite3.open(
            layout.databasePath,
            mode: OpenMode.readOnly,
          );
          try {
            final meta = database
                .select(
                  'SELECT repository_revision, destruction_epoch FROM workspace_metadata',
                )
                .single;
            expect(meta['repository_revision'], 0);
            expect(meta['destruction_epoch'], 0);
            expect(
              database.select('SELECT * FROM managed_skills'),
              hasLength(1),
            );
            final selected = database
                .select(
                  'SELECT upstream_object_id, effective_object_id FROM current_revision_selection',
                )
                .single;
            expect(selected['upstream_object_id'], 'a' * 40);
            expect(selected['effective_object_id'], 'a' * 40);
          } finally {
            database.close();
          }
          expect(
            await File(
              path.join(layout.revisionStorePath(id), 'store.marker'),
            ).readAsString(),
            'old-store',
          );
          expect(
            await File(
              path.join(layout.revisionBundlePath(id), 'bundle.marker'),
            ).readAsString(),
            'old-bundle',
          );
          expect(
            await File(
              path.join(layout.repositoryCopyPath('reviewer'), 'SKILL.md'),
            ).readAsString(),
            'old',
          );
          final draft = layout.draftPath(id);
          if (kind == 'directory' || kind == 'inPlace') {
            expect(
              await File(path.join(draft, 'SKILL.md')).readAsString(),
              'latest user draft',
            );
          }
          if (kind == 'file') {
            expect(await File(draft).readAsString(), 'latest user file');
          }
          if (kind == 'link') {
            expect(
              await Link(draft).target(),
              path.join(temp.path, 'outside-user-draft'),
            );
          }
          expect(
            await File(
              path.join(temp.path, 'outside-user-draft', 'note'),
            ).readAsString(),
            'outside must survive',
          );
        },
      );
    }
  }
  test(
    'guarded Removal preserves a post-BCP new Draft without rolling back committed deletion',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'guarded-removal-after-commit-',
      );
      addTearDown(
        () => PlatformDurableWorkspaceFilesystem().removeOwnedPath(
          targetPath: temp.path,
          ownerRoot: temp.parent.path,
        ),
      );
      final outcome = await exerciseGuardedRemovalRace(
        workspaceRoot: temp.path,
        window: 'afterCommit',
        editKind: 'directory',
      );
      expect(outcome, isA<OperationCommittedFinalizationPending>());
      final layout = WorkspaceLayout(temp.path);
      final database = sqlite3.open(
        layout.databasePath,
        mode: OpenMode.readOnly,
      );
      try {
        expect(database.select('SELECT * FROM managed_skills'), isEmpty);
        expect(
          database
              .select('SELECT repository_revision FROM workspace_metadata')
              .single['repository_revision'],
          1,
        );
      } finally {
        database.close();
      }
      expect(
        await File(
          path.join(
            layout.draftPath(ManagedSkillId(destructiveCrashSkillId)),
            'SKILL.md',
          ),
        ).readAsString(),
        'latest user draft',
      );
    },
  );
}
