// Opt-in E2E against the user's real SkillDeck Workspace and Agent folders.
//
// It never runs unless SKILLDECK_REAL_WORKSPACE_E2E=true is defined, touches
// only one dedicated Skill, and always removes that Skill afterwards:
//
//   flutter test --no-pub -d macos \
//     --dart-define=SKILLDECK_REAL_WORKSPACE_E2E=true \
//     integration_test/skill_drift_real_workspace_e2e_test.dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/app/skills_manager_app.dart';
import 'package:skills_manager/features/skills/data/repositories/package_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/data/services/directory_picker.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_workspace/skills_workspace.dart' as package_workspace;
import 'package:window_manager/window_manager.dart';

import '../test/support/fake_app_translation_repository.dart';

const _enabled = bool.fromEnvironment('SKILLDECK_REAL_WORKSPACE_E2E');
const _slot = 'skilldeck-drift-e2e';
const _managedBody = 'Managed version one.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Workspace: review, export, restore, and keep external changes',
    skip: !_enabled,
    (tester) async {
      // main.dart does this; without it the shell's window-button calls
      // reach window_manager before it has a main window and abort.
      await windowManager.ensureInitialized();
      final home = Platform.environment['HOME']!;
      final workspaceRoot = p.join(
        home,
        'Library/Application Support/com.feiyuliu.skilldeck/agent_skills/workspace',
      );
      if (!Directory(workspaceRoot).existsSync()) {
        fail('Real Workspace not found; nothing was changed.');
      }
      final scratch = await Directory.systemTemp.createTemp('$_slot-');
      final source = Directory(p.join(scratch.path, 'source'));
      final exports = await Directory(p.join(scratch.path, 'exports')).create();
      await _writeSkill(source.path, name: _slot, body: _managedBody);

      final backend = package_workspace.createSkillsRepository(
        package_workspace.SkillsRepositoryConfiguration(
          rootPath: workspaceRoot,
          defaultLockWaitPolicy: package_workspace.LockWaitPolicy.wait(
            timeout: const Duration(seconds: 30),
          ),
        ),
      );
      final app = PackageSkillsWorkspaceRepository(backend: backend);
      await _completion(app.open());
      if (backend.snapshot.managedSkills.any((s) => s.slotKey == _slot)) {
        await app.close();
        fail('A Skill named $_slot already exists; nothing was changed.');
      }

      final targets = _require(
        await backend
            .inspectActivationTargets(
              package_workspace.InspectActivationTargetsRequest(
                scope: package_workspace.ActivationScope.global,
              ),
            )
            .completed,
        'inspect activation targets',
      );
      final linkTarget = _targetUnderOrFail(
        targets,
        p.join(home, '.agents/skills'),
      );
      final copyTarget = _copyTarget(targets, p.join(home, '.agents/skills'));
      _step(
        'link agent ${linkTarget.agentId}, copy agent ${copyTarget?.agentId}',
      );

      final installed = _require(
        await backend
            .install(
              package_workspace.InstallRequest(
                source: package_workspace.LocalSourceDescriptor(
                  locator: source.path,
                ),
                activationSelection:
                    package_workspace.ActivationSelection.explicit([
                      package_workspace.ActivationTarget(
                        agentId: linkTarget.agentId,
                        scope: package_workspace.ActivationScope.global,
                      ),
                    ]),
                activationMode:
                    package_workspace.RequestedActivationMode.symbolicLink,
              ),
            )
            .completed,
        'install',
      );
      if (installed is! package_workspace.InstallCompleted) {
        fail('Install needs a takeover; refusing to touch existing content.');
      }
      package_workspace.ManagedSkill managed() => backend.snapshot.managedSkills
          .singleWhere((skill) => skill.slotKey == _slot);
      final skillId = managed().id;
      final appSkillId = WorkspaceSkillId(skillId.value);
      final activationRoots = <String>{};

      addTearDown(() async {
        await _unmountApp(tester);
        final result = await backend
            .remove(
              package_workspace.RemoveRequest(
                managedSkillIds: {skillId},
                intent: package_workspace.DestructiveIntent(
                  reviewedRevision: backend.snapshot.revision,
                ),
              ),
            )
            .completed;
        _step('cleanup remove: ${result.failureOrNull?.code.name ?? 'ok'}');
        await app.close();
        await scratch.delete(recursive: true);
        for (final location in activationRoots) {
          expect(
            FileSystemEntity.typeSync(location, followLinks: false),
            FileSystemEntityType.notFound,
            reason: 'leftover activation $location',
          );
        }
      });

      if (copyTarget != null) {
        final activation = _require(
          await backend
              .activate(
                package_workspace.ActivateRequest(
                  managedSkillIds: {skillId},
                  selection: package_workspace.ActivationSelection.explicit([
                    package_workspace.ActivationTarget(
                      agentId: copyTarget.agentId,
                      scope: package_workspace.ActivationScope.global,
                    ),
                  ]),
                  mode: package_workspace.RequestedActivationMode.copy,
                ),
              )
              .completed,
          'activate copy',
        );
        if (activation is! package_workspace.ActivationCompleted) {
          fail('Copy activation needs a takeover.');
        }
      }
      // Activation locations are Agent skills roots; the Skill lives below.
      final linkLocation = p.join(
        managed().activations
            .singleWhere(
              (a) => a.mode == package_workspace.ActivationMode.symbolicLink,
            )
            .location,
        _slot,
      );
      final copyLocation = managed().activations
          .where((a) => a.mode == package_workspace.ActivationMode.copy)
          .map((a) => p.join(a.location, _slot))
          .firstOrNull;
      activationRoots.addAll([linkLocation, ?copyLocation]);
      final repositoryCopy = p.normalize(
        p.absolute(p.dirname(linkLocation), Link(linkLocation).targetSync()),
      );
      _step(
        'repository copy resolved; copy activation: ${copyLocation != null}',
      );

      Future<int> publishedCount() async => _require(
        await backend
            .inspectPublishedHistory(
              package_workspace.PublishedHistoryRequest(
                managedSkillId: skillId,
              ),
            )
            .completed,
        'history',
      ).revisions.length;

      // Integrity-only Snapshots keep the repository revision, and the App
      // Snapshot pipeline drops non-advancing revisions (#56).
      // When the UI misses an integrity change, a favorite toggle on the test
      // Skill advances the revision so the latest integrity is delivered.
      var integrityWorkarounds = 0;
      Future<void> showIntegrity(Finder finder, {required bool shown}) async {
        bool reached() => finder.evaluate().isNotEmpty == shown;
        try {
          await _pumpUntil(tester, reached, maxPumps: 120);
          return;
        } on TestFailure {
          integrityWorkarounds += 1;
          _step('integrity change not shown; advancing revision');
        }
        for (final favorite in [true, false]) {
          await _completion(
            app
                .setFavorite(skillId: appSkillId, isFavorite: favorite)
                .completed,
          );
        }
        await _pumpUntil(tester, reached);
      }

      Future<void> validate() async {
        final report = await _completion(
          app.validateWorkspace(skillIds: {appSkillId}).completed,
        );
        expect(report.driftedSkillIds, contains(appSkillId));
        await showIntegrity(
          find.byKey(const Key('skill-drift-review-action')),
          shown: true,
        );
      }

      Future<void> openReview() async {
        await _tapWhenHitTestable(
          tester,
          find.byKey(const Key('skill-drift-review-action')),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(const Key('skill-drift-review-dialog')),
        );
        await _pumpUntil(tester, () => _artifactRows().evaluate().isNotEmpty);
      }

      Future<void> pressAndClose(Key key) async {
        await _tapWhenHitTestable(tester, find.byKey(key));
        _step('  pressed $key');
        await _pumpUntilGone(
          tester,
          find.byKey(const Key('skill-drift-review-dialog')),
        );
        _step('  dialog closed');
        await showIntegrity(
          find.byKey(const Key('skill-drift-review-action')),
          shown: false,
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSkillListLayoutProvider.overrideWithValue(
              SkillListLayout.list,
            ),
            skillsWorkspaceRepositoryProvider.overrideWithValue(app),
            skillBrowserRepositoryProvider.overrideWithValue(
              WorkspaceSkillBrowserRepository(app),
            ),
            skillAcquisitionRepositoryProvider.overrideWithValue(
              WorkspaceSkillAcquisitionRepository(
                workspace: app,
                resolver: SkillSourceLocatorResolver(),
              ),
            ),
            directoryPickerProvider.overrideWithValue(
              _FixedDirectoryPicker(exports.path),
            ),
            desktopSupportedProvider.overrideWithValue(true),
            appNotificationPresenterProvider.overrideWithValue(
              const _NoopNotificationPresenter(),
            ),
            appTranslationRepositoryProvider.overrideWithValue(
              fakeAppTranslationRepository(),
            ),
          ],
          child: const SkillsManagerApp(locale: Locale('zh')),
        ),
      );
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('installed-search-button')),
      );
      // The field replaces the button only after the expand animation ends.
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('installed-search-field')),
      );
      await tester.enterText(
        find.byKey(const Key('installed-search-field')),
        _slot,
      );
      await _tapWhenHitTestable(tester, find.byKey(const Key('skill-$_slot')));
      await _pumpUntilFound(tester, find.byKey(const Key('skill-detail')));

      // 1–4: drift is detected without overwrite, exported, then restored.
      _step('1 detect');
      await _edit(repositoryCopy, 'External edit one.');
      await validate();
      expect(await _body(repositoryCopy), contains('External edit one.'));
      final historyBefore = await publishedCount();

      _step('2 review');
      await openReview();
      expect(
        find.byKey(const Key('skill-drift-artifact-repositoryCopy')),
        findsOneWidget,
      );

      _step('3 export');
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-export-repositoryCopy')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('skill-drift-exported-repositoryCopy')),
      );
      final exported = exports.listSync().whereType<Directory>().single;
      expect(p.basename(exported.path), startsWith('$_slot-external-'));
      expect(await _body(exported.path), contains('External edit one.'));

      _step('4 restore');
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-select-restore')),
      );
      await pressAndClose(const Key('skill-drift-restore'));
      expect(await _body(repositoryCopy), contains(_managedBody));
      expect(await _body(linkLocation), contains(_managedBody));
      expect(await publishedCount(), historyBefore);

      // 5: keep the Repository Copy as a new revision.
      _step('5 keep repository copy');
      await _edit(repositoryCopy, 'External edit two.');
      await validate();
      await openReview();
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-select-repositoryCopy')),
      );
      await pressAndClose(const Key('skill-drift-keep'));
      expect(await publishedCount(), historyBefore + 1);
      expect(await _body(linkLocation), contains('External edit two.'));
      if (copyLocation != null) {
        expect(await _body(copyLocation), contains('External edit two.'));
      }

      // 6: two different external versions; keep the copy Activation's.
      if (copyLocation != null) {
        _step('6 multi-location');
        await _edit(repositoryCopy, 'Repository edit three.');
        await _edit(copyLocation, 'Copy edit three.');
        await validate();
        await openReview();
        final activationRow = _artifactRows()
            .evaluate()
            .map(_keyOf)
            .singleWhere(
              (key) => key.startsWith('skill-drift-artifact-activation:'),
            );
        final activationId = activationRow.substring(
          'skill-drift-artifact-'.length,
        );
        expect(_artifactRows(), findsNWidgets(2));
        await _tapWhenHitTestable(
          tester,
          find.byKey(Key('skill-drift-select-$activationId')),
        );
        await pressAndClose(const Key('skill-drift-keep'));
        for (final location in [repositoryCopy, linkLocation, copyLocation]) {
          expect(await _body(location), contains('Copy edit three.'));
        }
      } else {
        _step('6 skipped: no ~/.cursor/skills copy target');
      }

      // 7: a wrong link target is restore-only.
      _step('7 wrong link target');
      final elsewhere = p.join(scratch.path, 'elsewhere');
      await _writeSkill(elsewhere, name: _slot, body: 'Elsewhere.');
      await Link(linkLocation).delete();
      await Link(linkLocation).create(elsewhere);
      await validate();
      await openReview();
      final linkRow = _artifactRows().evaluate().map(_keyOf).single;
      final linkId = linkRow.substring('skill-drift-artifact-'.length);
      expect(find.byKey(Key('skill-drift-select-$linkId')), findsNothing);
      // Restoring is the only resolution here, so it starts out chosen.
      await pressAndClose(const Key('skill-drift-restore'));
      expect(
        p.normalize(
          p.absolute(p.dirname(linkLocation), Link(linkLocation).targetSync()),
        ),
        repositoryCopy,
      );

      // 8: keeping a renamed Skill is rejected and the drift stays pending.
      _step('8 rename rejected');
      await _writeSkill(
        repositoryCopy,
        name: 'renamed-skill',
        body: 'Renamed.',
      );
      await validate();
      await openReview();
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-select-repositoryCopy')),
      );
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-keep')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('skill-drift-failure')),
      );
      expect(
        find.byKey(const Key('skill-drift-review-dialog')),
        findsOneWidget,
      );
      expect(await _body(repositoryCopy), contains('Renamed.'));
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-select-restore')),
      );
      await pressAndClose(const Key('skill-drift-restore'));

      // 9: changing the artifact after review makes the decision stale.
      _step('9 stale');
      await _edit(repositoryCopy, 'Stale edit A.');
      await validate();
      await openReview();
      await _edit(repositoryCopy, 'Stale edit B.');
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-restore')),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('skill-drift-stale')));
      expect(await _body(repositoryCopy), contains('Stale edit B.'));
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-reload')),
      );
      await _pumpUntil(tester, () => _artifactRows().evaluate().isNotEmpty);
      await pressAndClose(const Key('skill-drift-restore'));

      // 10–11: removal warns about drift; reopening starts from a fresh review.
      _step('10 remove warning');
      await _edit(repositoryCopy, 'Remove warning edit.');
      await validate();
      _step('10 open remove dialog');
      await _tapWhenHitTestable(tester, find.byKey(const Key('remove-skill')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('remove-skill-dialog')),
      );
      expect(
        find.byKey(const Key('remove-skill-drift-warning')),
        findsOneWidget,
      );
      await _tapWhenHitTestable(tester, find.byKey(const Key('remove-cancel')));
      await _pumpUntilGone(
        tester,
        find.byKey(const Key('remove-skill-dialog')),
      );
      expect(managed().id, skillId);

      _step('11 reopen');
      await openReview();
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-drift-close')),
      );
      await _pumpUntilGone(
        tester,
        find.byKey(const Key('skill-drift-review-dialog')),
      );
      await tester.tap(find.byKey(const Key('skill-drift-review-action')));
      await tester.pump();
      expect(_artifactRows(), findsNothing);
      await _pumpUntil(tester, () => _artifactRows().evaluate().isNotEmpty);
      await pressAndClose(const Key('skill-drift-restore'));
      expect(
        await _body(repositoryCopy),
        contains(
          copyLocation != null ? 'Copy edit three.' : 'External edit two.',
        ),
      );
      _step('done; integrity workarounds: $integrityWorkarounds');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

final _clock = Stopwatch()..start();

void _step(String message) =>
    debugPrint('[drift-e2e ${_clock.elapsed.inSeconds}s] $message');

/// An existing Agent root other than the shared one, preferring Agents this
/// development machine does not rely on.
package_workspace.ActivationTargetInfo? _copyTarget(
  List<package_workspace.ActivationTargetInfo> targets,
  String sharedRoot,
) {
  final candidates = targets
      .where(
        (t) =>
            !p.equals(t.location, sharedRoot) &&
            Directory(t.location).existsSync(),
      )
      .toList();
  bool inUse(String location) =>
      location.contains('/.claude/') || location.contains('/.codex/');
  return candidates.where((t) => !inUse(t.location)).firstOrNull ??
      candidates.firstOrNull;
}

package_workspace.ActivationTargetInfo _targetUnderOrFail(
  List<package_workspace.ActivationTargetInfo> targets,
  String root,
) => _targetUnder(targets, root) ?? (throw TestFailure('No agent at $root.'));

package_workspace.ActivationTargetInfo? _targetUnder(
  List<package_workspace.ActivationTargetInfo> targets,
  String root,
) {
  if (!Directory(root).existsSync()) return null;
  return targets
      .where(
        (t) =>
            p.equals(t.location, root) || p.equals(p.dirname(t.location), root),
      )
      .firstOrNull;
}

T _require<T>(package_workspace.SkillsResult<T> result, String operation) {
  if (result.failureOrNull case final failure?) {
    throw TestFailure('$operation failed: ${failure.code.name}');
  }
  return result.valueOrNull as T;
}

Future<T> _completion<T>(Future<WorkspaceCompletion<T>> completion) async {
  return switch (await completion) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => throw TestFailure(
      '${failure.operation.name} failed: ${failure.code.name}',
    ),
    WorkspaceCommittedPending() => throw TestFailure('Finalization pending.'),
  };
}

Finder _artifactRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('skill-drift-artifact-');
});

String _keyOf(Element element) =>
    (element.widget.key! as ValueKey<String>).value;

Future<void> _writeSkill(
  String directory, {
  required String name,
  required String body,
}) async {
  await _makeWritable(directory);
  await Directory(directory).create(recursive: true);
  await File(p.join(directory, 'SKILL.md')).writeAsString(
    '---\nname: $name\ndescription: Drift resolution E2E fixture.\n---\n\n'
    '# $name\n\n$body\n',
    flush: true,
  );
}

Future<void> _edit(String directory, String body) =>
    _writeSkill(directory, name: _slot, body: body);

Future<String> _body(String directory) =>
    File(p.join(directory, 'SKILL.md')).readAsString();

Future<void> _makeWritable(String directory) async {
  if (!Directory(directory).existsSync()) return;
  final result = await Process.run('chmod', ['-R', 'u+w', directory]);
  if (result.exitCode != 0) throw TestFailure('chmod failed for $directory');
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) =>
    _pumpUntil(tester, () => finder.evaluate().isNotEmpty);

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) =>
    _pumpUntil(tester, () => finder.evaluate().isEmpty);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 1200,
}) async {
  final watch = Stopwatch()..start();
  void report(String outcome, int pumps) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      _step('slow wait $outcome: ${watch.elapsed.inSeconds}s, $pumps pumps');
    }
  }

  for (var attempt = 0; attempt < maxPumps; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 25));
    if (condition()) {
      report('ok', attempt + 1);
      return;
    }
  }
  report('timeout', maxPumps);
  throw TestFailure('Timed out waiting for the expected state.');
}

Future<void> _tapWhenHitTestable(WidgetTester tester, Finder finder) async {
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  final target = finder.hitTestable();
  await _pumpUntilFound(tester, target);
  await tester.tap(target.first);
  await tester.pump();
}

Future<void> _unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

final class _FixedDirectoryPicker implements DirectoryPicker {
  const _FixedDirectoryPicker(this.path);
  final String path;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => path;
}

final class _NoopNotificationPresenter implements AppNotificationPresenter {
  const _NoopNotificationPresenter();

  @override
  void present(AppNotificationPresentation presentation) {}

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}
