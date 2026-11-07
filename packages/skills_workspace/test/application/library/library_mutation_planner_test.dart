import 'package:skills_workspace/src/application/library/library_mutation_planner.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

const _skillId = '123e4567-e89b-42d3-a456-426614174000';
const _tagId = '123e4567-e89b-42d3-b456-426614174001';
const _newTagId = '123e4567-e89b-42d3-8456-426614174002';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  final planner = LibraryMutationPlanner(tagIds: () => _newTagId);
  final now = DateTime.utc(2026, 8, 17, 12);

  test('favorite and note plans preserve the other user-data field', () {
    final snapshot = _snapshot(
      skill: _skill(
        favorite: const SkillFavorite(isFavorite: false),
        note: SkillNote(text: 'Keep me', updatedAt: now),
      ),
    );

    final favorite =
        planner.setFavorite(
              snapshot: snapshot,
              managedSkillId: ManagedSkillId(_skillId),
              isFavorite: true,
              changedAt: now.add(const Duration(minutes: 1)),
            )
            as LibraryMutationPlan<void>;
    final favoriteChange =
        favorite.changes.mutations.single as PutSkillUserData;
    expect(favorite.changed, isTrue);
    expect(favoriteChange.favorite, isTrue);
    expect(favoriteChange.note, 'Keep me');
    expect(favoriteChange.noteUpdatedAtMicros, now.microsecondsSinceEpoch);

    final note =
        planner.saveNote(
              snapshot: _snapshot(skill: _skill(favorite: _favorite(now))),
              managedSkillId: ManagedSkillId(_skillId),
              text: ' Updated ',
              updatedAt: now.add(const Duration(minutes: 2)),
            )
            as LibraryMutationPlan<void>;
    final noteChange = note.changes.mutations.single as PutSkillUserData;
    expect(noteChange.favorite, isTrue);
    expect(noteChange.note, 'Updated');
    expect(noteChange.favoriteChangedAtMicros, now.microsecondsSinceEpoch);
  });

  test('clearing the final user-data field deletes the sparse row', () {
    final plan =
        planner.deleteNote(
              snapshot: _snapshot(
                skill: _skill(
                  note: SkillNote(text: 'Delete me', updatedAt: now),
                ),
              ),
              managedSkillId: ManagedSkillId(_skillId),
            )
            as LibraryMutationPlan<void>;

    expect(plan.changes.mutations.single, isA<DeleteSkillUserData>());
  });

  test('idempotent user-data writes and missing Skills are explicit', () {
    final unchanged =
        planner.setFavorite(
              snapshot: _snapshot(skill: _skill(favorite: _favorite(now))),
              managedSkillId: ManagedSkillId(_skillId),
              isFavorite: true,
              changedAt: now,
            )
            as LibraryMutationPlan<void>;
    expect(unchanged.changed, isFalse);
    expect(unchanged.changes.isEmpty, isTrue);

    final missing =
        planner.deleteNote(
              snapshot: RepositorySnapshot.empty(),
              managedSkillId: ManagedSkillId(_skillId),
            )
            as LibraryPlanningFailure<void>;
    expect(missing.code, LibraryPlanningFailureCode.managedSkillNotFound);
  });

  test('creates a normalized Personal Tag and rejects equivalent names', () {
    final created =
        planner.createTag(
              snapshot: _snapshot(skill: _skill()),
              name: '  Wórk  ',
              color: '#FFCC00',
              createdAt: now,
            )
            as LibraryMutationPlan<PersonalTag>;
    final mutation = created.changes.mutations.single as PutPersonalTag;
    expect(created.value.id, _newTagId);
    expect(created.value.name, 'Wórk');
    expect(mutation.normalizedKey, 'WÓRK');

    final duplicate =
        planner.createTag(
              snapshot: _snapshot(
                skill: _skill(),
                tags: [_tag(name: 'Wórk', createdAt: now)],
              ),
              name: 'wo\u0301rk',
              color: null,
              createdAt: now,
            )
            as LibraryPlanningFailure<PersonalTag>;
    expect(duplicate.code, LibraryPlanningFailureCode.duplicatePersonalTag);
  });

  test('updates tags without changing identity or creation time', () {
    final current = _tag(name: 'Old', createdAt: now);
    final updatedAt = now.add(const Duration(hours: 1));
    final plan =
        planner.updateTag(
              snapshot: _snapshot(skill: _skill(), tags: [current]),
              tagId: _tagId,
              name: 'New',
              color: '#112233',
              updatedAt: updatedAt,
            )
            as LibraryMutationPlan<PersonalTag>;
    final mutation = plan.changes.mutations.single as PutPersonalTag;

    expect(plan.value.id, current.id);
    expect(plan.value.createdAt, current.createdAt);
    expect(plan.value.updatedAt, updatedAt);
    expect(mutation.createdAtMicros, now.microsecondsSinceEpoch);
    expect(mutation.updatedAtMicros, updatedAt.microsecondsSinceEpoch);
  });

  test('assignment plans validate both identities and are idempotent', () {
    final taggedSkill = _skill(personalTagIds: const [_tagId]);
    final snapshot = _snapshot(
      skill: taggedSkill,
      tags: [_tag(name: 'Work', createdAt: now)],
    );

    final unchanged =
        planner.assignTag(
              snapshot: snapshot,
              managedSkillId: ManagedSkillId(_skillId),
              tagId: _tagId,
              createdAt: now,
            )
            as LibraryMutationPlan<void>;
    expect(unchanged.changed, isFalse);

    final removed =
        planner.unassignTag(
              snapshot: snapshot,
              managedSkillId: ManagedSkillId(_skillId),
              tagId: _tagId,
            )
            as LibraryMutationPlan<void>;
    expect(removed.changes.mutations.single, isA<DeleteSkillTagAssignment>());

    final missingTag =
        planner.assignTag(
              snapshot: _snapshot(skill: _skill()),
              managedSkillId: ManagedSkillId(_skillId),
              tagId: _tagId,
              createdAt: now,
            )
            as LibraryPlanningFailure<void>;
    expect(missingTag.code, LibraryPlanningFailureCode.personalTagNotFound);
  });

  test('deleting a tag is explicit and does not plan per-Skill deletes', () {
    final plan =
        planner.deleteTag(
              snapshot: _snapshot(
                skill: _skill(personalTagIds: const [_tagId]),
                tags: [_tag(name: 'Work', createdAt: now)],
              ),
              tagId: _tagId,
            )
            as LibraryMutationPlan<void>;

    expect(plan.changes.mutations, hasLength(1));
    expect(plan.changes.mutations.single, isA<DeletePersonalTag>());
  });
}

RepositorySnapshot _snapshot({
  required ManagedSkill skill,
  List<PersonalTag> tags = const [],
}) => RepositorySnapshot(
  revision: RepositoryRevision(7),
  managedSkills: [skill],
  personalTags: tags,
);

ManagedSkill _skill({
  SkillFavorite favorite = const SkillFavorite(isFavorite: false),
  SkillNote? note,
  List<String> personalTagIds = const [],
}) => ManagedSkill(
  id: ManagedSkillId(_skillId),
  slotKey: 'reviewer',
  declaredName: 'reviewer',
  displayName: 'Reviewer',
  description: 'Reviews Skills.',
  source: LocalSourceDescriptor(locator: '/tmp/reviewer'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _hash,
    fileCount: 1,
    byteSize: 64,
    publishedAt: DateTime.utc(2026),
  ),
  favorite: favorite,
  note: note,
  personalTagIds: personalTagIds,
);

SkillFavorite _favorite(DateTime changedAt) =>
    SkillFavorite(isFavorite: true, changedAt: changedAt);

PersonalTag _tag({required String name, required DateTime createdAt}) =>
    PersonalTag(
      id: _tagId,
      name: name,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
