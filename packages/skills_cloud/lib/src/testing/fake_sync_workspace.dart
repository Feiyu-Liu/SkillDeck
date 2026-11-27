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
  final drafts = <String>{},
      conflicts = <String>{},
      syncedOriginSkills = <String>{};
  final activations = <String, Set<String>>{};
  final extraData = <String, Map<String, Object?>>{};
  int _next = 0;
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
    );
    _skills[skill.id] = skill;
    _changed(skill.id);
    return skill;
  }

  WorkspaceSkill publish(String id, Map<String, String> edits) {
    final local = _skills[id]!, files = _files(local.effective)..addAll(edits);
    final next = _commit([local.effective], files);
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
  }) {
    final commit = _commit([], {
      'SKILL.md': '---\nname: $name\n---\n',
      'body.txt': 'replacement-${_next++}',
    });
    final result = WorkspaceSkill(
      id: id,
      effective: commit.id,
      upstream: source.isAdoptedSnapshot ? null : commit.id,
      source: source,
      declaredName: name,
      slotKey: slotKeyForName(name)!,
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
      skillIds: _changes.skip(start),
      cursor: '${_changes.length}',
    );
  }

  void _changed(String id) => _changes.add(id);
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
        return WorkspaceInstalled(occupant.id);
      }
      return WorkspaceSlotOccupied(occupant.id);
    }
    final id = 'skill-${_next++}';
    _skills[id] = WorkspaceSkill(
      id: id,
      effective: effective,
      upstream: upstream,
      source: source,
      declaredName: name,
      slotKey: slot,
    );
    if (source.isDeviceBound) syncedOriginSkills.add(id);
    installCount++;
    _changed(id);
    return WorkspaceInstalled(id);
  }

  @override
  Future<WorkspaceApply> remove({
    required String managedSkillId,
    required String expectedEffective,
  }) async {
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    if (local.effective != expectedEffective) {
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
    required String effective,
    required String? upstream,
    required String packPath,
  }) async {
    applyCount++;
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    if (local.effective != expectedEffective) {
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
  }) async {
    final local = _skills[managedSkillId];
    if (local == null) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.skillNotFound);
    }
    if (local.effective != expectedEffective) {
      return const WorkspaceApplyFailed(WorkspaceFailureCode.staleSnapshot);
    }
    if (local.source == source &&
        local.effective == effective &&
        local.upstream == upstream) {
      return const WorkspaceNoChange();
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
    _skills[managedSkillId] = WorkspaceSkill(
      id: managedSkillId,
      effective: effective,
      upstream: upstream,
      source: source,
      declaredName: name,
      slotKey: slot,
    );
    if (source.isDeviceBound) {
      syncedOriginSkills.add(managedSkillId);
    } else {
      syncedOriginSkills.remove(managedSkillId);
    }
    _changed(managedSkillId);
    return const WorkspaceSourceReplaced();
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
  );
}
