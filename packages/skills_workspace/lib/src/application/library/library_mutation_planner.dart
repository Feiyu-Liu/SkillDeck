import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/workspace_business_changes.dart';

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
    final value = text.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
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
    final normalized = _normalizeTagName(name);
    if (_findByKey(snapshot, normalized.key) != null) {
      return const LibraryPlanningFailure<PersonalTag>(
        LibraryPlanningFailureCode.duplicatePersonalTag,
      );
    }
    final id = _tagIds();
    final tag = PersonalTag(
      id: id,
      name: normalized.displayName,
      color: color,
      createdAt: createdAt.toUtc(),
      updatedAt: createdAt.toUtc(),
    );
    return LibraryMutationPlan<PersonalTag>(
      changes: WorkspaceBusinessChangeSet(
        mutations: [
          PutPersonalTag(
            personalTagId: id,
            normalizedKey: normalized.key,
            displayName: normalized.displayName,
            color: color,
            createdAtMicros: _micros(createdAt),
            updatedAtMicros: _micros(createdAt),
          ),
        ],
      ),
      changed: true,
      value: tag,
    );
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
    final normalized = _normalizeTagName(name);
    final conflicting = _findByKey(snapshot, normalized.key);
    if (conflicting != null && conflicting.id != tagId) {
      return const LibraryPlanningFailure<PersonalTag>(
        LibraryPlanningFailureCode.duplicatePersonalTag,
      );
    }
    if (current.name == normalized.displayName && current.color == color) {
      return LibraryMutationPlan<PersonalTag>(
        changes: WorkspaceBusinessChangeSet.empty,
        changed: false,
        value: current,
      );
    }
    final updated = PersonalTag(
      id: current.id,
      name: normalized.displayName,
      color: color,
      createdAt: current.createdAt,
      updatedAt: updatedAt.toUtc(),
    );
    return LibraryMutationPlan<PersonalTag>(
      changes: WorkspaceBusinessChangeSet(
        mutations: [
          PutPersonalTag(
            personalTagId: current.id,
            normalizedKey: normalized.key,
            displayName: normalized.displayName,
            color: color,
            createdAtMicros: _micros(current.createdAt),
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
    if (_normalizeTagName(tag.name).key == key) return tag;
  }
  return null;
}

_NormalizedTagName _normalizeTagName(String value) {
  final displayName = unicode.nfc(value.trim());
  if (displayName.isEmpty || displayName.contains('\u0000')) {
    throw ArgumentError.value(value, 'name', 'must not be empty');
  }
  return _NormalizedTagName(
    displayName: displayName,
    key: unicode.nfkc(displayName).toUpperCase(),
  );
}

int _micros(DateTime value) => value.toUtc().microsecondsSinceEpoch;

final class _NormalizedTagName {
  const _NormalizedTagName({required this.displayName, required this.key});

  final String displayName;
  final String key;
}
