import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'skill_json.dart';

/// A safe, structured error; never includes input in its string representation.
final class SkillSelectionFailure implements Exception {
  const SkillSelectionFailure(this.code, {this.details = const {}});
  final String code;
  final Map<String, Object?> details;
}

/// Resolves one immutable Snapshot, with the GUI's observed update signal.
/// No filesystem access, registration, network checks, or provider reads.
List<WorkspaceSkill> resolveSkillSelection(
  SkillsWorkspaceSnapshot snapshot,
  SkillSelection selection, {
  Set<WorkspaceSkillId> availableUpdateIds = const {},
}) {
  if (selection.isEmpty) throw const SkillSelectionFailure('usage');
  final ids = <WorkspaceSkillId>{};
  for (final ref in selection.refs) {
    final skill =
        snapshot.skills.where((s) => s.id.value == ref).firstOrNull ??
        snapshot.findSkillBySlotKey(ref);
    if (skill == null) {
      final safe = stripLocatorUserinfo(ref)
          .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '');
      throw SkillSelectionFailure(
        'skillNotFound',
        details: {'ref': String.fromCharCodes(safe.runes.take(200))},
      );
    }
    ids.add(skill.id);
  }
  final all = selection.all || selection.refs.isEmpty;
  final project = selection.projectPath;
  if (project != null && !p.isAbsolute(project)) {
    throw const SkillSelectionFailure('usage');
  }
  final skills = snapshot.skills.where((skill) {
    if (!all && !ids.contains(skill.id)) return false;
    final names = {
      for (final id in skill.personalTagIds)
        if (snapshot.findPersonalTag(id) case final tag?)
          tag.name.toLowerCase(),
    };
    if (!selection.tags.every((tag) => names.contains(tag.toLowerCase()))) {
      return false;
    }
    if (selection.untagged && skill.personalTagIds.isNotEmpty) return false;
    if (selection.favorite && !skill.isFavorite) return false;
    if (selection.sourcePrefix case final prefix?) {
      if (!stripLocatorUserinfo(skill.source.locator).startsWith(prefix)) {
        return false;
      }
    }
    if (selection.activeFor case final agent?) {
      if (!skill.activations.any((a) => a.agentIds.contains(agent))) {
        return false;
      }
    }
    if (project != null &&
        !skill.activations.any((a) {
          if (a.scope != WorkspaceScope.project) return false;
          final rootPath =
              a.projectRootPath ??
              snapshot.projectRoots
                  .where((r) => r.id == a.projectRootId)
                  .firstOrNull
                  ?.path;
          return rootPath != null &&
              p.equals(p.normalize(rootPath), p.normalize(project));
        })) {
      return false;
    }
    if (selection.hasUpdate && !availableUpdateIds.contains(skill.id)) {
      return false;
    }
    return true;
  }).toList();
  // GUI default: case-insensitive display name, then Slot Key.
  skills.sort((a, b) {
    final name = a.displayName.toLowerCase().compareTo(
      b.displayName.toLowerCase(),
    );
    return name == 0 ? a.slotKey.compareTo(b.slotKey) : name;
  });
  return List.unmodifiable(skills);
}
