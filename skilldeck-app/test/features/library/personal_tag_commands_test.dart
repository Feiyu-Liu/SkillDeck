import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/library/personal_tag_palette.dart';
import 'package:skills_manager/features/library/personal_tag_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../support/fake_skills_workspace_repository.dart';

void main() {
  test('creates a tag with an unused palette color and assigns it', () async {
    final (:workspace, :container) = await _open(tags: [_tag('Writing')]);
    final commands = container.read(personalTagCommandsProvider.notifier);

    final failure = await commands.create(' Frontend ', assignTo: _skillId);

    expect(failure, isNull);
    final created = workspace.createdPersonalTags.single;
    expect(created.name, 'Frontend');
    expect(created.color, isNot('#3E63DD'));
    expect(personalTagPalette, contains(created.color));
    final tagId = workspace.current.personalTags.last.id;
    expect(workspace.assignedPersonalTags, [(skillId: _skillId, tagId: tagId)]);
    expect(container.read(personalTagCountsProvider), {tagId: 1});
  });

  test('returns duplicate names to the caller without a toast', () async {
    final (:workspace, :container) = await _open(tags: [_tag('Writing')]);
    final commands = container.read(personalTagCommandsProvider.notifier);

    final failure = await commands.create('writing', assignTo: _skillId);

    expect(
      (failure! as WorkspaceFailure).code,
      WorkspaceErrorCode.duplicatePersonalTag,
    );
    expect(workspace.assignedPersonalTags, isEmpty);
    expect(container.read(appNotificationControllerProvider), isNull);
  });

  test('rename keeps the color and recolor keeps the name', () async {
    final tag = _tag('Writing');
    final (:workspace, :container) = await _open(tags: [tag]);
    final commands = container.read(personalTagCommandsProvider.notifier);

    await commands.rename(tag, 'Docs');
    await commands.rename(tag, ' Writing ');
    await commands.recolor(tag, '#30A46C');

    expect(workspace.updatedPersonalTags, [
      (tagId: tag.id, name: 'Docs', color: '#3E63DD'),
      (tagId: tag.id, name: 'Writing', color: '#30A46C'),
    ]);
  });

  test('surfaces assignment failures as a toast', () async {
    final (:workspace, :container) = await _open(tags: const []);
    final commands = container.read(personalTagCommandsProvider.notifier);

    await commands.assign(skillId: _skillId, tagId: 'missing');

    expect(container.read(appNotificationControllerProvider), isNotNull);
    expect(workspace.current.skills.single.personalTagIds, isEmpty);
  });

  test('deleting a tag drops it from the active filter', () async {
    final keep = _tag('Writing');
    final drop = _tag('Docs', id: 'tag-docs');
    final (:workspace, :container) = await _open(tags: [keep, drop]);
    container.listen(personalTagFilterProvider, (_, _) {});
    final filter = container.read(personalTagFilterProvider.notifier)
      ..toggle(keep.id)
      ..toggle(drop.id);
    expect(container.read(personalTagFilterProvider), {keep.id, drop.id});

    await container.read(personalTagCommandsProvider.notifier).delete(drop.id);
    await pumpEventQueue();

    expect(container.read(personalTagFilterProvider), {keep.id});
    filter.toggle(keep.id);
    expect(container.read(personalTagFilterProvider), isEmpty);
  });

  test('orders tags by name and counts assignments', () async {
    final (:workspace, :container) = await _open(
      tags: [
        _tag('writing'),
        _tag('Agents', id: 'tag-agents'),
      ],
      skillTagIds: const ['tag-agents'],
    );

    expect(container.read(personalTagsProvider).map((tag) => tag.name), [
      'Agents',
      'writing',
    ]);
    expect(container.read(personalTagCountsProvider), {'tag-agents': 1});
  });
}

Future<({FakeSkillsWorkspaceRepository workspace, ProviderContainer container})>
_open({
  required List<WorkspacePersonalTag> tags,
  List<String> skillTagIds = const [],
}) async {
  final workspace = FakeSkillsWorkspaceRepository(
    snapshot: SkillsWorkspaceSnapshot(
      revision: 1,
      projectRoots: const [],
      personalTags: tags,
      skills: [
        WorkspaceSkill(
          id: _skillId,
          slotKey: 'alpha',
          declaredName: 'alpha',
          displayName: 'Alpha',
          description: '',
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
          personalTagIds: skillTagIds,
        ),
      ],
    ),
  );
  final container = ProviderContainer(
    overrides: [skillsWorkspaceRepositoryProvider.overrideWithValue(workspace)],
  );
  addTearDown(container.dispose);
  container.listen(workspaceSnapshotProvider, (_, _) {});
  await container.read(workspaceSnapshotProvider.future);
  return (workspace: workspace, container: container);
}

WorkspacePersonalTag _tag(String name, {String id = 'tag-writing'}) =>
    WorkspacePersonalTag(
      id: id,
      name: name,
      color: '#3E63DD',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final _skillId = WorkspaceSkillId('managed-alpha');
