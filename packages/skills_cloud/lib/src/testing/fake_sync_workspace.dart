import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../sync/portable_source.dart';
import '../sync/sync_workspace.dart';
import 'fake_pack.dart';

/// Test Workspace owns ancestry and merges; production Reconciler never does.
final class FakeSyncWorkspace implements SyncWorkspace {
  @override
  String? slotKeyForName(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9._]+'), '-')
        .replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
    return normalized.isEmpty
        ? null
        : normalized.substring(
            0,
            normalized.length > 255 ? 255 : normalized.length,
          );
  }

  final _skills = <String, WorkspaceSkill>{};
  final _commits = <String, FakeCommit>{};
  final _blobs = <String, String>{};
  final _changes = <String>[];
  static const _vocabularyChange = '@vocabulary';
  final _metadata = <String, WorkspaceSkillMetadata>{};
  final _tags = <String, WorkspaceTag>{};
  int _nextTag = 0;
  void Function()? beforeMetadataApply;
  void Function()? beforeTagApply;
  final drafts = <String>{},
      conflicts = <String>{},
      syncedOriginSkills = <String>{};
  final activations = <String, Set<String>>{};
  final extraData = <String, Map<String, Object?>>{};
  int _next = 0;
  int _nextSourceEpoch = 0;
  int installCount = 0, applyCount = 0;
  int? exportSize;
  WorkspaceSkill seed({
    required PortableSource source,
    String name = 'fixture',
    Map<String, String>? files,
  }) {
    final commit = _commit(
      [],
      files ?? {'SKILL.md': '---\nname: $name\n---\n', 'body.txt': 'base'},
    );
    final skill = WorkspaceSkill(
      id: 'skill-${_next++}',
      effective: commit.id,
      upstream: source.isAdoptedSnapshot ? null : commit.id,
      source: source,
      declaredName: name,
      slotKey: slotKeyForName(name)!,
      sourceEpoch: 'source-${_nextSourceEpoch++}',
    );
    _skills[skill.id] = skill;
    _changed(skill.id);
    return skill;
  }

  WorkspaceSkill publish(
    String id,
    Map<String, String> edits, {
    String? mergeParent,
  }) {
    final local = _skills[id]!, files = _files(local.effective)..addAll(edits);
    final next = _commit([local.effective, ?mergeParent], files);
    final result = _with(
      local,
      effective: next.id,
      name: _name(next, local.declaredName),
    );
    _skills[id] = result;
    drafts.remove(id);
    conflicts.remove(id);
    _changed(id);
    return result;
  }

  WorkspaceSkill replaceLocally(
    String id,
    PortableSource source, {
    String name = 'fixture',
    bool preserveSelection = false,
  }) {
    final prior = _skills[id]!;
    final effective = preserveSelection
        ? prior.effective
        : _commit([], {
            'SKILL.md': '---\nname: $name\n---\n',
            'body.txt': 'replacement-${_next++}',
          }).id;
    final result = WorkspaceSkill(
      id: id,
      effective: effective,
      upstream: preserveSelection
          ? prior.upstream
          : source.isAdoptedSnapshot
          ? null
          : effective,
      source: source,
      declaredName: name,
      slotKey: slotKeyForName(name)!,
      sourceEpoch: 'source-${_nextSourceEpoch++}',
    );
    _skills[id] = result;
    _changed(id);
    return result;
  }

  void removeLocally(String id) {
    _skills.remove(id);
    _changed(id);
  }

  Map<String, String> files(String id) => _files(_skills[id]!.effective);
  @override
  Future<List<WorkspaceSkill>> listSkills() async =>
      List.unmodifiable(_skills.values);
  @override
  Future<WorkspaceSkill?> inspectRevisionSelections(
    String managedSkillId,
  ) async => _skills[managedSkillId];
  @override
  Future<WorkspaceChanges> inspectCommittedChanges(String? cursor) async {
    final start = cursor == null ? 0 : int.parse(cursor);
    return WorkspaceChanges(
      skillIds: _changes.skip(start).where((id) => id != _vocabularyChange),
      cursor: '${_changes.length}',
      vocabularyChanged: _changes.skip(start).contains(_vocabularyChange),
    );
  }

  void _changed(String id) => _changes.add(id);

  void editMetadata(
    String skillId, {
    required bool favorite,
    required String? note,
    required Iterable<String> tagIds,
  }) {
    _metadata[skillId] = WorkspaceSkillMetadata(
      favorite: favorite,
      note: note,
      tagIds: tagIds,
    );
    _changed(skillId);
  }

  WorkspaceTag createLocalTag(String name, {String? color}) {
    final matching = _tags.values
        .where((tag) => tag.normalizedName == name.trim().toUpperCase())
        .firstOrNull;
    if (matching != null) return matching;
    final tag = WorkspaceTag(
      id: 'tag-${_nextTag++}',
      name: name.trim(),
      normalizedName: name.trim().toUpperCase(),
      color: color?.toUpperCase(),
    );
    _tags[tag.id] = tag;
    _changed(_vocabularyChange);
    return tag;
  }

  WorkspaceTag editTag(
    String id, {
    required String name,
    required String? color,
  }) {
    final old = _tags[id]!;
    final normalizedName = name.trim().toUpperCase();
    final target = _tags.values
        .where((tag) => tag.id != id && tag.normalizedName == normalizedName)
        .firstOrNull;
    if (target != null) {
      _removeTag(id, replacement: target.id);
    }
    final tag = WorkspaceTag(
      id: target?.id ?? id,
      name: name.trim(),
      normalizedName: normalizedName,
      color: color?.toUpperCase(),
    );
    if (tag.id != old.id || tag.name != old.name || tag.color != old.color) {
      _tags[tag.id] = tag;
      _changed(_vocabularyChange);
    }
    return tag;
  }

  void removeLocalTag(String id) => _removeTag(id);

  void _removeTag(String id, {String? replacement}) {
    if (_tags.remove(id) == null) return;
    _changed(_vocabularyChange);
    for (final entry in _metadata.entries.toList()) {
      final metadata = entry.value;
      if (metadata.tagIds.contains(id)) {
        editMetadata(
          entry.key,
          favorite: metadata.favorite,
          note: metadata.note,
          tagIds: {...metadata.tagIds, ?replacement}..remove(id),
        );
      }
    }
  }

  @override
  String tagClientKey(String localTagId) => sha256
      .convert(utf8.encode('fake-device-${identityHashCode(this)}:$localTagId'))
      .toString();

  @override
  Future<WorkspaceMetadataSnapshot> inspectMetadata() async =>
      WorkspaceMetadataSnapshot(
        revision: '${_changes.length}',
        skills: {
          for (final id in _skills.keys)
            id:
                _metadata[id] ??
                WorkspaceSkillMetadata(
                  favorite: false,
                  note: null,
                  tagIds: const {},
                ),
        },
        tags: _tags,
      );

  @override
  Future<WorkspaceApply> applyMetadata({
    required String managedSkillId,
    required String expectedRevision,
    required bool favorite,
    required String? note,
    required Set<String> tagIds,
  }) async {
    beforeMetadataApply?.call();
    if (expectedRevision != '${_changes.length}') {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    if (!_skills.containsKey(managedSkillId)) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    editMetadata(
      managedSkillId,
      favorite: favorite,
      note: note,
      tagIds: tagIds,
    );
    return const WorkspaceNoChange();
  }

  @override
  Future<WorkspaceTagApply> ensureTag({
    required String expectedRevision,
    required String name,
    required String? color,
  }) async {
    if (_staleTag(expectedRevision)) {
      return const WorkspaceTagApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    final matching = _tags.values
        .where((tag) => tag.normalizedName == name.trim().toUpperCase())
        .firstOrNull;
    final applied = matching == null
        ? createLocalTag(name, color: color)
        : editTag(matching.id, name: name, color: color);
    return WorkspaceTagApplied(localTagId: applied.id);
  }

  @override
  Future<WorkspaceTagApply> updateTag({
    required String expectedRevision,
    required String localTagId,
    required String name,
    required String? color,
  }) async {
    if (_staleTag(expectedRevision)) {
      return const WorkspaceTagApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    return WorkspaceTagApplied(
      localTagId: editTag(localTagId, name: name, color: color).id,
    );
  }

  @override
  Future<WorkspaceTagApply> deleteTag({
    required String expectedRevision,
    required String localTagId,
  }) async {
    if (_staleTag(expectedRevision)) {
      return const WorkspaceTagApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    _removeTag(localTagId);
    return const WorkspaceTagApplied();
  }

  bool _staleTag(String expectedRevision) {
    beforeTagApply?.call();
    return expectedRevision != '${_changes.length}';
  }

  @override
  Future<WorkspaceTagApply> renameTags({
    required String expectedRevision,
    required Map<String, String> names,
  }) async {
    if (_staleTag(expectedRevision)) {
      return const WorkspaceTagApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    final occupied = _tags.values
        .where((tag) => !names.containsKey(tag.id))
        .map((tag) => tag.normalizedName)
        .toSet();
    final changed = <String, WorkspaceTag>{};
    for (final entry in names.entries) {
      final name = entry.value.trim(), key = name.toUpperCase();
      final original = _tags[entry.key];
      if (original == null || !occupied.add(key)) {
        return const WorkspaceTagApplyFailed(
          WorkspaceFailureCode.operationFailed,
        );
      }
      changed[entry.key] = WorkspaceTag(
        id: entry.key,
        name: name,
        normalizedName: key,
        color: original.color,
      );
    }
    _tags.addAll(changed);
    _changed(_vocabularyChange);
    return const WorkspaceTagApplied();
  }

  @override
  Future<WorkspaceExport> exportRevisionPack(
    String managedSkillId,
    String destination,
  ) async {
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceExportFailed(WorkspaceFailureCode.skillNotFound);
    }
    final target = File(destination);
    if (await target.exists()) {
      return const WorkspaceExportFailed(
        WorkspaceFailureCode.destinationUnusable,
      );
    }
    if (exportSize case final size?) {
      final out = await target.open(mode: FileMode.write);
      await out.truncate(size);
      await out.close();
    } else {
      final roots = [local.effective, ?local.upstream],
          seen = <String>{},
          pending = [...roots];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (seen.add(id)) pending.addAll(_commits[id]!.parents);
      }
      final commits = seen.map((id) => _commits[id]!).toList(),
          used = commits.expand((c) => c.files.values).toSet();
      await target.writeAsBytes(
        FakePack(commits, {for (final id in used) id: _blobs[id]!}).encode(),
      );
    }
    return WorkspaceExported(
      effective: local.effective,
      upstream: local.upstream,
    );
  }

  Future<FakePack?> _read(
    String path,
    String effective,
    String? upstream,
  ) async {
    try {
      final pack = FakePack.decode(await File(path).readAsBytes());
      if (!pack.containsClosure([effective, ?upstream])) return null;
      return pack;
    } on Exception {
      return null;
    }
  }

  void _import(FakePack pack) {
    _commits.addAll(pack.commits);
    _blobs.addAll(pack.blobs);
  }

  @override
  Future<WorkspaceApply> install({
    required String packPath,
    required String effective,
    required String? upstream,
    required PortableSource source,
  }) async {
    if (source.isAdoptedSnapshot != (upstream == null)) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.invalidSkill);
    }
    final pack = await _read(packPath, effective, upstream);
    if (pack == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.invalidPack);
    }
    _import(pack);
    final name = _name(pack.commits[effective]!, 'fixture'),
        slot = slotKeyForName(name)!;
    final occupant = _skills.values.where((s) => s.slotKey == slot).firstOrNull;
    if (occupant != null) {
      if (occupant.source == source &&
          occupant.effective == effective &&
          occupant.upstream == upstream) {
        return WorkspaceInstalled(
          occupant.id,
          sourceEpoch: occupant.sourceEpoch,
        );
      }
      return WorkspaceSlotOccupied(occupant.id);
    }
    final id = 'skill-${_next++}';
    final sourceEpoch = 'source-${_nextSourceEpoch++}';
    _skills[id] = WorkspaceSkill(
      id: id,
      effective: effective,
      upstream: upstream,
      source: source,
      declaredName: name,
      slotKey: slot,
      sourceEpoch: sourceEpoch,
    );
    if (source.isDeviceBound) syncedOriginSkills.add(id);
    installCount++;
    _changed(id);
    return WorkspaceInstalled(id, sourceEpoch: sourceEpoch);
  }

  @override
  Future<WorkspaceApply> remove({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
  }) async {
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    if (local.effective != expectedEffective ||
        (expectedSourceEpoch != null &&
            local.sourceEpoch != expectedSourceEpoch)) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    if (drafts.contains(managedSkillId) || conflicts.contains(managedSkillId)) {
      return const WorkspaceDraftRequired();
    }
    _skills.remove(managedSkillId);
    _changed(managedSkillId);
    return const WorkspaceRemoved();
  }

  @override
  Future<WorkspaceApply> applyContent({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
    required String effective,
    required String? upstream,
    required String packPath,
  }) async {
    applyCount++;
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    if (local.effective != expectedEffective ||
        (expectedSourceEpoch != null &&
            local.sourceEpoch != expectedSourceEpoch)) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    final incoming = await _read(packPath, effective, upstream);
    if (incoming == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.invalidPack);
    }
    _import(incoming);
    final graph = FakePack(_commits.values, _blobs);
    if (graph.descends(local.effective, effective)) {
      return const WorkspaceNoChange();
    }
    if (drafts.contains(managedSkillId) || conflicts.contains(managedSkillId)) {
      return const WorkspaceDraftRequired();
    }
    final selectedUpstream =
        upstream == null ||
            local.upstream != null && graph.descends(local.upstream!, upstream)
        ? local.upstream
        : upstream;
    if (graph.descends(effective, local.effective)) {
      _skills[managedSkillId] = _with(
        local,
        effective: effective,
        upstream: selectedUpstream,
      );
      _changed(managedSkillId);
      return const WorkspaceFastForwarded();
    }
    final ancestors = <String>{}, pending = [local.effective];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (ancestors.add(id)) pending.addAll(_commits[id]?.parents ?? []);
    }
    final search = [effective], seen = <String>{};
    String? base;
    while (search.isNotEmpty) {
      final id = search.removeAt(0);
      if (!seen.add(id)) continue;
      if (ancestors.contains(id)) {
        base = id;
        break;
      }
      search.addAll(_commits[id]?.parents ?? []);
    }
    if (base == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.invalidPack);
    }
    final original = _files(base),
        left = _files(local.effective),
        right = _files(effective),
        merged = <String, String>{};
    for (final path in {...original.keys, ...left.keys, ...right.keys}) {
      final a = left[path], b = right[path], before = original[path];
      if (a != b && a != before && b != before) {
        conflicts.add(managedSkillId);
        return const WorkspaceConflicted();
      }
      final selected = a == before ? b : a;
      if (selected != null) merged[path] = selected;
    }
    final commit = _commit([local.effective, effective], merged);
    _skills[managedSkillId] = _with(
      local,
      effective: commit.id,
      upstream: selectedUpstream,
    );
    _changed(managedSkillId);
    return WorkspaceMerged(commit.id);
  }

  @override
  Future<WorkspaceApply> replaceSource({
    required String managedSkillId,
    required String expectedEffective,
    required String packPath,
    required String effective,
    required String? upstream,
    required PortableSource source,
    String? expectedSourceEpoch,
  }) async {
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    if (local.effective != expectedEffective ||
        (expectedSourceEpoch != null &&
            local.sourceEpoch != expectedSourceEpoch)) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    if (expectedSourceEpoch == null &&
        local.source == source &&
        local.effective == effective &&
        local.upstream == upstream) {
      return WorkspaceNoChange(sourceEpoch: local.sourceEpoch);
    }
    if (drafts.contains(managedSkillId) || conflicts.contains(managedSkillId)) {
      return const WorkspaceDraftRequired();
    }
    final pack = await _read(packPath, effective, upstream);
    if (pack == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.invalidPack);
    }
    _import(pack);
    final name = _name(pack.commits[effective]!, 'fixture'),
        slot = slotKeyForName(name)!,
        occupant = _skills.values
            .where((s) => s.id != managedSkillId && s.slotKey == slot)
            .firstOrNull;
    if (occupant != null) return WorkspaceSlotOccupied(occupant.id);
    final sourceEpoch = 'source-${_nextSourceEpoch++}';
    _skills[managedSkillId] = WorkspaceSkill(
      id: managedSkillId,
      effective: effective,
      upstream: upstream,
      source: source,
      declaredName: name,
      slotKey: slot,
      sourceEpoch: sourceEpoch,
    );
    if (source.isDeviceBound) {
      syncedOriginSkills.add(managedSkillId);
    } else {
      syncedOriginSkills.remove(managedSkillId);
    }
    _changed(managedSkillId);
    return WorkspaceSourceReplaced(sourceEpoch: sourceEpoch);
  }

  Map<String, String> _files(String revision) => _commits[revision]!.files.map(
    (path, digest) => MapEntry(path, _blobs[digest]!),
  );
  FakeCommit _commit(List<String> parents, Map<String, String> content) {
    final files = <String, String>{};
    for (final path in content.keys.toList()..sort()) {
      final text = content[path]!,
          digest = sha256.convert(utf8.encode(text)).toString();
      _blobs[digest] = text;
      files[path] = digest;
    }
    final id = sha1
        .convert(utf8.encode(jsonEncode({'parents': parents, 'files': files})))
        .toString();
    final commit = FakeCommit(id: id, parents: parents, files: files);
    _commits[id] = commit;
    return commit;
  }

  String _name(FakeCommit c, String fallback) =>
      RegExp(
        r'^name:\s*(.+)$',
        multiLine: true,
      ).firstMatch(_blobs[c.files['SKILL.md']] ?? '')?.group(1)?.trim() ??
      fallback;
  WorkspaceSkill _with(
    WorkspaceSkill old, {
    required String effective,
    String? upstream,
    String? name,
  }) => WorkspaceSkill(
    id: old.id,
    effective: effective,
    upstream: upstream ?? old.upstream,
    source: old.source,
    declaredName: name ?? old.declaredName,
    slotKey: slotKeyForName(name ?? old.declaredName)!,
    sourceEpoch: old.sourceEpoch,
  );
}
