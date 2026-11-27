import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../api/cloud_api.dart';
import '../api/cloud_result.dart';
import '../api/cloud_values.dart';
import '../feed_check_scheduler.dart';
import '../sign_in/cloud_sign_in.dart';
import 'portable_source.dart';
import 'sync_outcome.dart';
import 'sync_state_store.dart';
import 'sync_workspace.dart';

final class SyncBootstrap {
  SyncBootstrap({
    required Iterable<String> installedSkillIds,
    required Map<String, SyncOutcome> outcomes,
    required this.completed,
  }) : installedSkillIds = Set.unmodifiable(installedSkillIds),
       outcomes = Map.unmodifiable(outcomes);
  final Set<String> installedSkillIds;

  /// Keyed by Lineage ID, including those that could not be installed.
  final Map<String, SyncOutcome> outcomes;
  final bool completed;
}

/// State reconciliation for one account/device. Serialize calls through the App.
/// Workspace failures that indicate a broken contract throw a stable StateError;
/// they are not converted into a permanently pending Sync Status.
final class Reconciler {
  Reconciler({
    required this.api,
    required this.workspace,
    required this.state,
    required this.scratchDirectory,
  });
  final CloudApi api;
  final SyncWorkspace workspace;
  final SyncStateStore state;
  final String scratchDirectory;
  final _outcomes = <String, SyncOutcome>{};
  Map<String, SyncOutcome> get outcomes => Map.unmodifiable(_outcomes);
  Duration? _retryAfter;

  Future<SyncOutcome> startSyncing(String skillId) async {
    final old = (await state.links())
        .where((l) => l.managedSkillId == skillId)
        .firstOrNull;
    final link = old ?? SyncLink(managedSkillId: skillId, clientKey: _uuid());
    if (old == null) await state.put(link);
    return _record(skillId, await _reconcile(link));
  }

  Future<SyncOutcome> stopSyncing(String skillId) async {
    final link = await _link(skillId);
    if (link?.lineageId == null) {
      await state.unlink(skillId);
      return _record(skillId, const SkillDeviceOnly());
    }
    final result = await api.stop(link!.lineageId!);
    if (result is CloudApiSuccess<Lineage>) {
      await state.unlink(skillId);
      return _record(skillId, const SkillDeviceOnly());
    }
    if (result is ApiLineageEnded && result.lineage != null) {
      return _record(skillId, await _reconcile(link, result.lineage));
    }
    return _record(skillId, _failure(result));
  }

  Future<FeedCheckResult> checkLocalChanges() async {
    final changes = await workspace.inspectCommittedChanges(
      await state.workspaceCursor(),
    );
    var success = true;
    for (final link in await state.links()) {
      if (!changes.skillIds.contains(link.managedSkillId) &&
          link.lineageId != null) {
        continue;
      }
      final result = _record(link.managedSkillId, await _reconcile(link));
      success = _settled(result) && success;
    }
    if (success) await state.setWorkspaceCursor(changes.cursor);
    return success
        ? FeedCheckResult.success(retryAfter: _retryAfter)
        : FeedCheckResult.failure(retryAfter: _retryAfter);
  }

  Future<FeedCheckResult> feedCheck() async {
    _retryAfter = null;
    var success = true;
    for (final pending in (await state.links()).where(
      (l) => l.lineageId == null,
    )) {
      success =
          _settled(
            _record(pending.managedSkillId, await _reconcile(pending)),
          ) &&
          success;
    }
    if (await state.feedCursor() == null) {
      final result = await bootstrap();
      if (!result.completed) {
        return FeedCheckResult.failure(retryAfter: _retryAfter);
      }
    }
    while (true) {
      final result = await api.checkFeed(after: await state.feedCursor());
      if (result is ApiCursorExpired) {
        final reset = await bootstrap(reset: true);
        return reset.completed
            ? FeedCheckResult.success()
            : FeedCheckResult.failure();
      }
      if (result is! CloudApiSuccess<FeedPage>) {
        _failure(result);
        return FeedCheckResult.failure(retryAfter: _retryAfter);
      }
      _retryAfter = result.retryAfter;
      final page = result.value;
      var pageSettled = true;
      for (final entry in page.entries) {
        if (!entry.isLineage || (await state.exclusions()).contains(entry.id)) {
          continue;
        }
        final link = (await state.links())
            .where((l) => l.lineageId == entry.id)
            .firstOrNull;
        if (link != null && entry.version <= link.version) continue;
        final remote = await api.readLineage(entry.id);
        SyncOutcome outcome;
        if (remote is CloudApiSuccess<Lineage>) {
          outcome = link == null
              ? (await _materialize(remote.value)).outcome
              : await _reconcile(link, remote.value);
        } else {
          outcome = remote is ApiNotFound
              ? const SyncNeedsAttention(AttentionReason.missingAfterReset)
              : _failure(remote);
        }
        _record(link?.managedSkillId ?? entry.id, outcome);
        pageSettled = _settled(outcome) && pageSettled;
      }
      success = pageSettled && success;
      if (!pageSettled) break;
      await state.setFeedCursor(page.cursor);
      if (!page.more) break;
    }
    return success
        ? FeedCheckResult.success(retryAfter: _retryAfter)
        : FeedCheckResult.failure(retryAfter: _retryAfter);
  }

  Future<SyncOutcome> reconcileSkill(String managedSkillId) async {
    final link = await _link(managedSkillId);
    if (link == null) return const SkillDeviceOnly();
    return _record(managedSkillId, await _reconcile(link));
  }

  Future<SyncOutcome> _reconcile(SyncLink initial, [Lineage? remote]) async {
    var link = initial;
    for (var attempt = 0; attempt < 3; attempt++) {
      var local = await workspace.inspectRevisionSelections(
        link.managedSkillId,
      );
      if (link.lineageId == null) {
        if (local == null) {
          await state.unlink(link.managedSkillId);
          return const SkillRemoved();
        }
        final created = await api.createLineage(
          clientKey: link.clientKey!,
          source: local.source.toJson(),
        );
        if (created is! CloudApiSuccess<Lineage>) return _failure(created);
        remote = created.value;
        link = SyncLink(
          managedSkillId: link.managedSkillId,
          lineageId: remote.id,
          clientKey: link.clientKey,
          generation: remote.generation,
        );
        await state.put(link);
      }
      if (remote == null) {
        final read = await api.readLineage(link.lineageId!);
        if (read is ApiNotFound) {
          return const SyncNeedsAttention(AttentionReason.missingAfterReset);
        }
        if (read is! CloudApiSuccess<Lineage>) return _failure(read);
        remote = read.value;
      }
      if (remote.state == LineageState.stopped) {
        await state.unlink(link.managedSkillId);
        return const SkillDeviceOnly();
      }
      if (remote.state == LineageState.removed) {
        if (local != null) {
          final applied = await workspace.remove(
            managedSkillId: local.id,
            expectedEffective: local.effective,
          );
          if (applied is WorkspaceDraftRequired) {
            return const SyncNeedsAttention(AttentionReason.removedWithDraft);
          }
          if (applied is WorkspaceApplyFailed &&
              applied.code == WorkspaceFailureCode.staleSnapshot) {
            remote = null;
            continue;
          }
          if (applied is! WorkspaceRemoved &&
              !(applied is WorkspaceApplyFailed &&
                  applied.code == WorkspaceFailureCode.skillNotFound)) {
            _workspaceDefect();
          }
        }
        await state.unlink(link.managedSkillId);
        return const SkillRemoved();
      }
      if (local == null) {
        final removed = await api.remove(remote.id);
        if (removed is! CloudApiSuccess<Lineage>) return _failure(removed);
        await state.unlink(link.managedSkillId);
        return const SkillRemoved();
      }
      final source = PortableSource.fromJson(remote.source), head = remote.head;
      if (head != null &&
          local.source == source &&
          local.effective == head.effective &&
          local.upstream == head.upstream) {
        await _remember(link, remote);
        return const SkillSynced();
      }
      if (remote.generation > link.generation) {
        if (local.effective != link.effective) {
          return const SyncNeedsAttention(
            AttentionReason.sourceReplacedWithLocalChanges,
          );
        }
        return _replace(link, remote, local);
      }
      final sourceChanged = local.source != source;
      if (head != null && !sourceChanged) {
        final applied = await _download(
          remote,
          (path) => workspace.applyContent(
            managedSkillId: local!.id,
            expectedEffective: local.effective,
            effective: head.effective,
            upstream: head.upstream,
            packPath: path,
          ),
        );
        if (applied.error != null) return applied.error!;
        switch (applied.value!) {
          case WorkspaceDraftRequired():
            return const SyncNeedsAttention(AttentionReason.incomingDraft);
          case WorkspaceConflicted():
            return SyncNeedsAttention(
              AttentionReason.syncMergeConflict,
              deviceName: head.deviceName,
            );
          case WorkspaceApplyFailed(code: WorkspaceFailureCode.staleSnapshot):
            remote = null;
            continue;
          case WorkspaceFastForwarded():
            await _remember(link, remote);
            return const SkillSynced();
          case WorkspaceNoChange():
          case WorkspaceMerged():
            break;
          default:
            _workspaceDefect();
        }
        local = await workspace.inspectRevisionSelections(local.id);
        if (local == null) {
          remote = null;
          continue;
        }
        if (local.effective == head.effective &&
            local.upstream == head.upstream) {
          await _remember(link, remote);
          return const SkillSynced();
        }
      }
      final uploaded = await _upload(
        local,
        remote,
        changeGeneration: sourceChanged,
      );
      switch (uploaded) {
        case CloudApiSuccess<Lineage>(:final value):
          await _remember(link, value);
          return const SkillSynced();
        case ApiStaleHead(:final lineage):
          remote = lineage;
        case ApiWrongGeneration(:final lineage):
          remote = lineage;
        case ApiLineageEnded(:final lineage):
          remote = lineage;
        case ApiPackMissing():
          remote = null;
        default:
          return _failure(uploaded);
      }
    }
    return const WaitingToUpload();
  }

  Future<CloudApiResult<Lineage>> _upload(
    WorkspaceSkill local,
    Lineage remote, {
    required bool changeGeneration,
  }) async {
    final path = await _scratch();
    try {
      final export = await workspace.exportRevisionPack(local.id, path);
      if (export is! WorkspaceExported) _workspaceDefect();
      final file = File(path);
      if (await file.length() > CloudApi.maxPackBytes) {
        return const ApiPackTooLarge(PackSizeLimit.packed);
      }
      final digest = PackDigest(
        (await sha256.bind(file.openRead()).single).toString(),
      );
      final generation = remote.generation + (changeGeneration ? 1 : 0);
      final sent = await api.uploadPack(
        remote.id,
        generation: generation,
        path: path,
        digest: digest,
        effective: export.effective,
        upstream: export.upstream,
      );
      if (sent is CloudApiError) return sent;
      // Re-read to avoid combining an exported revision with a concurrently replaced Source/name.
      final current = await workspace.inspectRevisionSelections(local.id);
      if (current == null ||
          current.source != local.source ||
          current.effective != export.effective ||
          current.upstream != export.upstream) {
        return const ApiUnavailable(CloudFailureCode.server);
      }
      final head = LineageHead(
        effective: export.effective,
        upstream: export.upstream,
        pack: digest,
        declaredName: current.declaredName,
      );
      return await (changeGeneration
          ? api.changeGeneration(
              remote.id,
              expectedGeneration: remote.generation,
              source: current.source.toJson(),
              next: head,
            )
          : api.advanceHead(
              remote.id,
              generation: generation,
              expected: remote.head,
              next: head,
            ));
    } finally {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<({WorkspaceApply? value, SyncOutcome? error})> _download(
    Lineage remote,
    Future<WorkspaceApply> Function(String) apply,
  ) async {
    final path = await _scratch(), head = remote.head!;
    try {
      final result = await api.downloadPack(
        remote.id,
        generation: remote.generation,
        digest: head.pack,
        path: path,
      );
      if (result is ApiNotFound) {
        return (value: null, error: const WaitingToUpload());
      }
      if (result is! CloudApiSuccess<String>) {
        return (value: null, error: _failure(result));
      }
      return (value: await apply(path), error: null);
    } finally {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _remember(SyncLink link, Lineage remote) => state.put(
    SyncLink(
      managedSkillId: link.managedSkillId,
      lineageId: remote.id,
      version: remote.version,
      generation: remote.generation,
      effective: remote.head?.effective,
    ),
  );
  Future<SyncLink?> _link(String skillId) async => (await state.links())
      .where((l) => l.managedSkillId == skillId)
      .firstOrNull;
  SyncOutcome _record(String id, SyncOutcome outcome) {
    _outcomes[id] = outcome;
    return outcome;
  }

  SyncOutcome _failure(CloudApiResult<Object?> result) {
    if (result is ApiPackTooLarge) {
      return const SyncNeedsAttention(AttentionReason.tooLarge);
    }
    if (result is ApiUnavailable) {
      _retryAfter = result.retryAfter;
      if (result.code == CloudFailureCode.protocol) {
        throw StateError('cloud_protocol');
      }
      return const WaitingToUpload();
    }
    if (result is ApiSignInRequired || result is ApiStorageLimitReached) {
      return SyncAccountCondition(result as CloudApiError);
    }
    throw StateError('cloud_protocol');
  }

  Never _workspaceDefect() => throw StateError('cloud_workspace_contract');
  bool _settled(SyncOutcome result) =>
      result is SkillSynced ||
      result is SkillDeviceOnly ||
      result is SkillRemoved;
  Future<String> _scratch() async {
    await Directory(scratchDirectory).create(recursive: true);
    return '$scratchDirectory/${_uuid()}.pack';
  }

  Future<SyncBootstrap> bootstrap({bool reset = false}) async {
    final library = <Lineage>[];
    String? cursor, feedCursor;
    do {
      final response = await api.listLibrary(cursor: cursor);
      if (response is! CloudApiSuccess<LibraryPage>) {
        _failure(response);
        return SyncBootstrap(
          installedSkillIds: [],
          outcomes: {},
          completed: false,
        );
      }
      if (feedCursor != null && feedCursor != response.value.feedCursor) {
        throw StateError('cloud_protocol');
      }
      feedCursor = response.value.feedCursor;
      library.addAll(response.value.lineages);
      cursor = response.value.next;
    } while (cursor != null);
    final results = <String, SyncOutcome>{}, installed = <String>{};
    var completed = true;
    for (final remote in library) {
      if ((await state.exclusions()).contains(remote.id)) continue;
      final result = await _materialize(remote);
      results[remote.id] = result.outcome;
      _record(remote.id, result.outcome);
      if (result.installed != null) installed.add(result.installed!);
      if (!_settled(result.outcome)) completed = false;
    }
    if (reset) {
      final present = library.map((l) => l.id).toSet();
      for (final link in await state.links()) {
        if (link.lineageId != null && !present.contains(link.lineageId)) {
          const reason = SyncNeedsAttention(AttentionReason.missingAfterReset);
          results[link.lineageId!] = reason;
          _record(link.managedSkillId, reason);
        }
      }
    }
    if (completed) await state.setFeedCursor(feedCursor);
    return SyncBootstrap(
      installedSkillIds: installed,
      outcomes: results,
      completed: completed,
    );
  }

  Future<({SyncOutcome outcome, String? installed})> _materialize(
    Lineage remote,
  ) async {
    if (remote.state != LineageState.live || remote.head == null) {
      return (outcome: const SkillDeviceOnly(), installed: null);
    }
    final linked = (await state.links())
        .where((l) => l.lineageId == remote.id)
        .firstOrNull;
    if (linked != null) {
      return (outcome: await _reconcile(linked, remote), installed: null);
    }
    final source = PortableSource.fromJson(remote.source), head = remote.head!;
    final existing = (await workspace.listSkills())
        .where(
          (s) =>
              s.source == source &&
              s.slotKey == workspace.slotKeyForName(head.declaredName) &&
              s.effective == head.effective,
        )
        .firstOrNull;
    if (existing != null) {
      if ((await state.links()).any((l) => l.managedSkillId == existing.id)) {
        return (
          outcome: SyncNeedsAttention(
            AttentionReason.slotOccupied,
            occupant: existing.id,
          ),
          installed: null,
        );
      }
      final link = SyncLink(
        managedSkillId: existing.id,
        lineageId: remote.id,
        generation: remote.generation,
      );
      await state.put(link);
      return (outcome: await _reconcile(link, remote), installed: null);
    }
    final applied = await _download(
      remote,
      (path) => workspace.install(
        packPath: path,
        effective: head.effective,
        upstream: head.upstream,
        source: source,
      ),
    );
    if (applied.error != null) {
      return (outcome: applied.error!, installed: null);
    }
    if (applied.value case WorkspaceSlotOccupied(:final occupant)) {
      return (
        outcome: SyncNeedsAttention(
          AttentionReason.slotOccupied,
          occupant: occupant,
        ),
        installed: null,
      );
    }
    if (applied.value case WorkspaceInstalled(:final managedSkillId)) {
      await _remember(SyncLink(managedSkillId: managedSkillId), remote);
      return (outcome: const SkillSynced(), installed: managedSkillId);
    }
    _workspaceDefect();
  }

  Future<void> exclude(String lineageId) async {
    await state.setExcluded(lineageId, true);
    for (final link in (await state.links()).where(
      (l) => l.lineageId == lineageId,
    )) {
      await state.unlink(link.managedSkillId);
      _record(link.managedSkillId, const SkillDeviceOnly());
    }
  }

  Future<void> include(String lineageId) async {
    await state.setExcluded(lineageId, false);
    // Re-list after a local exclusion changes, even when the remote version did not.
    await state.setFeedCursor(null);
  }

  Future<SyncOutcome> keepDeviceOnly(String skillId) async {
    final link = await _link(skillId);
    if (link?.lineageId != null) {
      await exclude(link!.lineageId!);
    } else {
      await state.unlink(skillId);
    }
    return _record(skillId, const SkillDeviceOnly());
  }

  Future<SyncOutcome> removeMissingLocally(String skillId) async {
    final local = await workspace.inspectRevisionSelections(skillId);
    if (local != null) {
      final applied = await workspace.remove(
        managedSkillId: skillId,
        expectedEffective: local.effective,
      );
      if (applied is WorkspaceDraftRequired) {
        return _record(
          skillId,
          const SyncNeedsAttention(AttentionReason.removedWithDraft),
        );
      }
      if (applied is! WorkspaceRemoved) _workspaceDefect();
    }
    await state.unlink(skillId);
    return _record(skillId, const SkillRemoved());
  }

  Future<SyncOutcome> uploadAsNewLineage(String skillId) async {
    await state.unlink(skillId);
    return startSyncing(skillId);
  }

  /// Explicit acceptance discards this Device's unpublished-to-Cloud revisions.
  /// A Dirty Draft still requires the Workspace's ordinary draft resolution.
  Future<SyncOutcome> acceptReplacement(String skillId) async {
    final link = await _link(skillId),
        local = await workspace.inspectRevisionSelections(skillId);
    if (link?.lineageId == null || local == null) {
      throw StateError('cloud_workspace_contract');
    }
    final result = await api.readLineage(link!.lineageId!);
    if (result is! CloudApiSuccess<Lineage>) return _failure(result);
    return _record(skillId, await _replace(link, result.value, local));
  }

  /// Replaces the occupying local Skill only after an explicit user choice.
  Future<SyncOutcome> replaceOccupied(String lineageId, String occupant) async {
    if ((await state.links()).any(
      (link) => link.lineageId == lineageId && link.managedSkillId != occupant,
    )) {
      throw ArgumentError(
        'Resolve the occupied slot locally before retrying the linked Skill.',
      );
    }
    final priorLink = await _link(occupant);
    final local = await workspace.inspectRevisionSelections(occupant);
    if (local == null) throw StateError('cloud_workspace_contract');
    final result = await api.readLineage(lineageId);
    if (result is! CloudApiSuccess<Lineage>) return _failure(result);
    final outcome = await _replace(
      SyncLink(managedSkillId: occupant, lineageId: lineageId),
      result.value,
      local,
    );
    if (outcome is SkillSynced &&
        priorLink?.lineageId != null &&
        priorLink!.lineageId != lineageId) {
      await state.setExcluded(priorLink.lineageId!, true);
    }
    return _record(occupant, outcome);
  }

  Future<SyncOutcome> _replace(
    SyncLink link,
    Lineage remote,
    WorkspaceSkill local,
  ) async {
    if (remote.state != LineageState.live || remote.head == null) {
      return _reconcile(link, remote);
    }
    final head = remote.head!,
        applied = await _download(
          remote,
          (path) => workspace.replaceSource(
            managedSkillId: local.id,
            expectedEffective: local.effective,
            packPath: path,
            effective: head.effective,
            upstream: head.upstream,
            source: PortableSource.fromJson(remote.source),
          ),
        );
    if (applied.error != null) return applied.error!;
    switch (applied.value!) {
      case WorkspaceSourceReplaced():
      case WorkspaceNoChange():
        await _remember(link, remote);
        return const SkillSynced();
      case WorkspaceDraftRequired():
        return const SyncNeedsAttention(AttentionReason.incomingDraft);
      case WorkspaceSlotOccupied(:final occupant):
        return SyncNeedsAttention(
          AttentionReason.slotOccupied,
          occupant: occupant,
        );
      case WorkspaceApplyFailed(code: WorkspaceFailureCode.staleSnapshot):
        return const WaitingToUpload();
      default:
        _workspaceDefect();
    }
  }
}

String _uuid() {
  final random = Random.secure(),
      bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
