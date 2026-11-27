import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/workspace_business_changes.dart';
import 'personal_tag_name.dart';

enum LibraryPlanningFailureCode {
  managedSkillNotFound,
  personalTagNotFound,
  duplicatePersonalTag,
}

sealed class LibraryPlanningResult<T> {
  const LibraryPlanningResult();
}

final class LibraryMutationPlan<T> extends LibraryPlanningResult<T> {
  const LibraryMutationPlan({
    required this.changes,
    required this.changed,
    required this.value,
  });

  final WorkspaceBusinessChangeSet changes;
  final bool changed;
  final T value;
}

final class LibraryPlanningFailure<T> extends LibraryPlanningResult<T> {
  const LibraryPlanningFailure(this.code);

  final LibraryPlanningFailureCode code;
}

typedef PersonalTagIdFactory = String Function();

/// Plans Favorite, Note, Personal Tag, and assignment mutations from one
/// immutable Snapshot. The resulting change set is persisted only through the
/// Operation Coordinator's business commit transaction.
final class LibraryMutationPlanner {
  const LibraryMutationPlanner({required PersonalTagIdFactory tagIds})
    : _tagIds = tagIds;

  final PersonalTagIdFactory _tagIds;

  LibraryPlanningResult<void> setMetadata({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required bool favorite,
    required String? note,
    required Set<String> tagIds,
    required DateTime updatedAt,
  }) {
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.managedSkillNotFound,
      );
    }
    final noteText = note == null ? null : _normalizeNote(note);
    for (final tagId in tagIds) {
      if (snapshot.findPersonalTag(tagId) == null) {
        return const LibraryPlanningFailure<void>(
          LibraryPlanningFailureCode.personalTagNotFound,
        );
      }
    }
    final favoriteChanged = skill.favorite.isFavorite != favorite;
    final existingFavoriteTime = skill.favorite.changedAt;
    final noteChanged = skill.note?.text != noteText;
    final assigned = skill.personalTagIds.toSet();
    final mutations = <WorkspaceBusinessMutation>[
      if (favoriteChanged || noteChanged)
        ..._userDataChange(
          skill,
          favorite: favorite,
          favoriteChangedAtMicros: favorite
              ? _micros(
                  favoriteChanged
                      ? updatedAt
                      : existingFavoriteTime ?? updatedAt,
                )
              : null,
          note: noteText,
          noteUpdatedAtMicros: noteText == null
              ? null
              : _micros(noteChanged ? updatedAt : skill.note!.updatedAt),
        ).mutations,
      for (final tagId in assigned.difference(tagIds))
        DeleteSkillTagAssignment(
          managedSkillId: skill.id,
          personalTagId: tagId,
        ),
      for (final tagId in tagIds.difference(assigned))
        PutSkillTagAssignment(
          managedSkillId: skill.id,
          personalTagId: tagId,
          createdAtMicros: _micros(updatedAt),
        ),
    ];
    return LibraryMutationPlan<void>(
      changes: WorkspaceBusinessChangeSet(mutations: mutations),
      changed: mutations.isNotEmpty,
      value: null,
    );
  }

  LibraryPlanningResult<void> setFavorite({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required bool isFavorite,
    required DateTime changedAt,
  }) {
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.managedSkillNotFound,
      );
    }
    if (skill.favorite.isFavorite == isFavorite) {
      return const LibraryMutationPlan<void>(
        changes: WorkspaceBusinessChangeSet.empty,
        changed: false,
        value: null,
      );
    }
    return LibraryMutationPlan<void>(
      changes: _userDataChange(
        skill,
        favorite: isFavorite,
        favoriteChangedAtMicros: isFavorite ? _micros(changedAt) : null,
        note: skill.note?.text,
        noteUpdatedAtMicros: skill.note == null
            ? null
            : _micros(skill.note!.updatedAt),
      ),
      changed: true,
      value: null,
    );
  }

  LibraryPlanningResult<void> saveNote({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required String text,
    required DateTime updatedAt,
  }) {
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.managedSkillNotFound,
      );
    }
    final value = _normalizeNote(text);
    if (skill.note?.text == value) {
      return const LibraryMutationPlan<void>(
        changes: WorkspaceBusinessChangeSet.empty,
        changed: false,
        value: null,
      );
    }
    return LibraryMutationPlan<void>(
      changes: _userDataChange(
        skill,
        favorite: skill.favorite.isFavorite,
        favoriteChangedAtMicros: skill.favorite.changedAt == null
            ? null
            : _micros(skill.favorite.changedAt!),
        note: value,
        noteUpdatedAtMicros: _micros(updatedAt),
      ),
      changed: true,
      value: null,
    );
  }

  LibraryPlanningResult<void> deleteNote({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
  }) {
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.managedSkillNotFound,
      );
    }
    if (skill.note == null) {
      return const LibraryMutationPlan<void>(
        changes: WorkspaceBusinessChangeSet.empty,
        changed: false,
        value: null,
      );
    }
    return LibraryMutationPlan<void>(
      changes: _userDataChange(
        skill,
        favorite: skill.favorite.isFavorite,
        favoriteChangedAtMicros: skill.favorite.changedAt == null
            ? null
            : _micros(skill.favorite.changedAt!),
        note: null,
        noteUpdatedAtMicros: null,
      ),
      changed: true,
      value: null,
    );
  }

  LibraryPlanningResult<PersonalTag> createTag({
    required RepositorySnapshot snapshot,
    required String name,
    required String? color,
    required DateTime createdAt,
  }) {
    final normalized = normalizePersonalTagName(name);
    if (_findByKey(snapshot, normalized.key) != null) {
      return const LibraryPlanningFailure<PersonalTag>(
        LibraryPlanningFailureCode.duplicatePersonalTag,
      );
    }
    return _putTag(normalized: normalized, color: color, updatedAt: createdAt);
  }

  LibraryPlanningResult<PersonalTag> updateTag({
    required RepositorySnapshot snapshot,
    required String tagId,
    required String name,
    required String? color,
    required DateTime updatedAt,
  }) {
    final current = snapshot.findPersonalTag(tagId);
    if (current == null) {
      return const LibraryPlanningFailure<PersonalTag>(
        LibraryPlanningFailureCode.personalTagNotFound,
      );
    }
    final normalized = normalizePersonalTagName(name);
    final conflicting = _findByKey(snapshot, normalized.key);
    if (conflicting != null && conflicting.id != tagId) {
      return const LibraryPlanningFailure<PersonalTag>(
        LibraryPlanningFailureCode.duplicatePersonalTag,
      );
    }
    return _putTag(
      normalized: normalized,
      color: color,
      updatedAt: updatedAt,
      current: current,
    );
  }

  LibraryMutationPlan<PersonalTag> ensureTag({
    required RepositorySnapshot snapshot,
    required String name,
    required String? color,
    required DateTime updatedAt,
  }) {
    final normalized = normalizePersonalTagName(name);
    return _putTag(
      normalized: normalized,
      color: color,
      updatedAt: updatedAt,
      current: _findByKey(snapshot, normalized.key),
    );
  }

  LibraryPlanningResult<PersonalTag> updateTagMerging({
    required RepositorySnapshot snapshot,
    required String tagId,
    required String name,
    required String? color,
    required DateTime updatedAt,
  }) {
    final current = snapshot.findPersonalTag(tagId);
    if (current == null) {
      return const LibraryPlanningFailure<PersonalTag>(
        LibraryPlanningFailureCode.personalTagNotFound,
      );
    }
    final normalized = normalizePersonalTagName(name);
    final survivor = _findByKey(snapshot, normalized.key) ?? current;
    final put = _putTag(
      normalized: normalized,
      color: color,
      updatedAt: updatedAt,
      current: survivor,
    );
    if (survivor.id == current.id) return put;

    return LibraryMutationPlan<PersonalTag>(
      changes: WorkspaceBusinessChangeSet(
        mutations: [
          ...put.changes.mutations,
          for (final skill in snapshot.managedSkills)
            if (skill.personalTagIds.contains(current.id) &&
                !skill.personalTagIds.contains(survivor.id))
              PutSkillTagAssignment(
                managedSkillId: skill.id,
                personalTagId: survivor.id,
                createdAtMicros: _micros(updatedAt),
              ),
          DeletePersonalTag(current.id),
        ],
      ),
      changed: true,
      value: put.value,
    );
  }

  LibraryPlanningResult<void> renameTags({
    required RepositorySnapshot snapshot,
    required Map<String, String> names,
    required DateTime updatedAt,
  }) {
    final usedFinalKeys = {
      for (final tag in snapshot.personalTags)
        if (!names.containsKey(tag.id)) normalizePersonalTagName(tag.name).key,
    };
    final finalNames = {
      for (final entry in names.entries)
        entry.key: normalizePersonalTagName(entry.value),
    };
    for (final name in finalNames.values) {
      if (!usedFinalKeys.add(name.key)) {
        return const LibraryPlanningFailure<void>(
          LibraryPlanningFailureCode.duplicatePersonalTag,
        );
      }
    }
    final reservedKeys = {
      ...usedFinalKeys,
      for (final tag in snapshot.personalTags)
        normalizePersonalTagName(tag.name).key,
    };
    final temporary = <PutPersonalTag>[];
    final renamed = <PutPersonalTag>[];
    for (final entry in finalNames.entries) {
      final current = snapshot.findPersonalTag(entry.key);
      if (current == null) {
        return const LibraryPlanningFailure<void>(
          LibraryPlanningFailureCode.personalTagNotFound,
        );
      }
      if (current.name == entry.value.displayName) continue;
      // Vacate the old unique keys within the same SQLite commit before
      // writing any final names. Assignment rows keep their original IDs.
      var temporaryKey = 'WORKSPACE-TAG-RENAME-${current.id.toUpperCase()}';
      while (!reservedKeys.add(temporaryKey)) {
        temporaryKey += '-';
      }
      temporary.add(
        PutPersonalTag(
          personalTagId: current.id,
          normalizedKey: temporaryKey,
          displayName: current.name,
          color: current.color,
          createdAtMicros: _micros(current.createdAt),
          updatedAtMicros: _micros(current.updatedAt),
        ),
      );
      renamed.add(
        PutPersonalTag(
          personalTagId: current.id,
          normalizedKey: entry.value.key,
          displayName: entry.value.displayName,
          color: current.color,
          createdAtMicros: _micros(current.createdAt),
          updatedAtMicros: _micros(updatedAt),
        ),
      );
    }
    return LibraryMutationPlan<void>(
      changes: WorkspaceBusinessChangeSet(
        mutations: [...temporary, ...renamed],
      ),
      changed: renamed.isNotEmpty,
      value: null,
    );
  }

  LibraryMutationPlan<PersonalTag> _putTag({
    required ({String displayName, String key}) normalized,
    required String? color,
    required DateTime updatedAt,
    PersonalTag? current,
  }) {
    if (current != null &&
        current.name == normalized.displayName &&
        current.color == color) {
      return LibraryMutationPlan<PersonalTag>(
        changes: WorkspaceBusinessChangeSet.empty,
        changed: false,
        value: current,
      );
    }
    final updated = PersonalTag(
      id: current?.id ?? _tagIds(),
      name: normalized.displayName,
      color: color,
      createdAt: current?.createdAt ?? updatedAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
    return LibraryMutationPlan<PersonalTag>(
      changes: WorkspaceBusinessChangeSet(
        mutations: [
          PutPersonalTag(
            personalTagId: updated.id,
            normalizedKey: normalized.key,
            displayName: normalized.displayName,
            color: color,
            createdAtMicros: _micros(updated.createdAt),
            updatedAtMicros: _micros(updatedAt),
          ),
        ],
      ),
      changed: true,
      value: updated,
    );
  }

  LibraryPlanningResult<void> deleteTag({
    required RepositorySnapshot snapshot,
    required String tagId,
  }) {
    if (snapshot.findPersonalTag(tagId) == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.personalTagNotFound,
      );
    }
    return LibraryMutationPlan<void>(
      changes: WorkspaceBusinessChangeSet(
        mutations: [DeletePersonalTag(tagId)],
      ),
      changed: true,
      value: null,
    );
  }

  LibraryPlanningResult<void> assignTag({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required String tagId,
    required DateTime createdAt,
  }) => _planAssignment(
    snapshot: snapshot,
    managedSkillId: managedSkillId,
    tagId: tagId,
    createdAt: createdAt,
    assign: true,
  );

  LibraryPlanningResult<void> unassignTag({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required String tagId,
  }) => _planAssignment(
    snapshot: snapshot,
    managedSkillId: managedSkillId,
    tagId: tagId,
    createdAt: null,
    assign: false,
  );

  LibraryPlanningResult<void> _planAssignment({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required String tagId,
    required DateTime? createdAt,
    required bool assign,
  }) {
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.managedSkillNotFound,
      );
    }
    if (snapshot.findPersonalTag(tagId) == null) {
      return const LibraryPlanningFailure<void>(
        LibraryPlanningFailureCode.personalTagNotFound,
      );
    }
    final assigned = skill.personalTagIds.contains(tagId);
    if (assigned == assign) {
      return const LibraryMutationPlan<void>(
        changes: WorkspaceBusinessChangeSet.empty,
        changed: false,
        value: null,
      );
    }
    final mutation = assign
        ? PutSkillTagAssignment(
            managedSkillId: managedSkillId,
            personalTagId: tagId,
            createdAtMicros: _micros(createdAt!),
          )
        : DeleteSkillTagAssignment(
            managedSkillId: managedSkillId,
            personalTagId: tagId,
          );
    return LibraryMutationPlan<void>(
      changes: WorkspaceBusinessChangeSet(mutations: [mutation]),
      changed: true,
      value: null,
    );
  }
}

WorkspaceBusinessChangeSet _userDataChange(
  ManagedSkill skill, {
  required bool favorite,
  required int? favoriteChangedAtMicros,
  required String? note,
  required int? noteUpdatedAtMicros,
}) {
  if (!favorite && note == null) {
    return WorkspaceBusinessChangeSet(
      mutations: [DeleteSkillUserData(skill.id)],
    );
  }
  return WorkspaceBusinessChangeSet(
    mutations: [
      PutSkillUserData(
        managedSkillId: skill.id,
        favorite: favorite,
        favoriteChangedAtMicros: favoriteChangedAtMicros,
        note: note,
        noteUpdatedAtMicros: noteUpdatedAtMicros,
      ),
    ],
  );
}

PersonalTag? _findByKey(RepositorySnapshot snapshot, String key) {
  for (final tag in snapshot.personalTags) {
    if (normalizePersonalTagName(tag.name).key == key) return tag;
  }
  return null;
}

String _normalizeNote(String text) {
  final value = text.trim();
  if (value.isEmpty) {
    throw ArgumentError.value(text, 'text', 'must not be empty');
  }
  return value;
}

int _micros(DateTime value) => value.toUtc().microsecondsSinceEpoch;
