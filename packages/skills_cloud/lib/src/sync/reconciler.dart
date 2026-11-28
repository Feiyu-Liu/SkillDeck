import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../api/cloud_api.dart';
import '../api/cloud_result.dart';
import '../api/cloud_values.dart';
import '../api/metadata_values.dart';
import '../feed_check_scheduler.dart';
import '../sign_in/cloud_sign_in.dart';
import 'portable_source.dart';
import 'metadata_reconciler.dart';
import 'sync_outcome.dart';
import 'sync_state_store.dart';
import 'sync_workspace.dart';

final class SyncBootstrap {
  SyncBootstrap({
    required Iterable<String> installedSkillIds,
    required Map<String, SyncOutcome> outcomes,
    required this.completed,
    this.retryAfter,
  }) : installedSkillIds = Set.unmodifiable(installedSkillIds),
       outcomes = Map.unmodifiable(outcomes),
       _accountCondition = null;

  const SyncBootstrap._unavailable(this._accountCondition, {this.retryAfter})
    : installedSkillIds = const {},
      outcomes = const {},
      completed = false;
  final Set<String> installedSkillIds;

  /// Keyed by Lineage ID, including those that could not be installed.
  final Map<String, SyncOutcome> outcomes;
  final bool completed;
  final Duration? retryAfter;
  final SyncAccountCondition? _accountCondition;
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
  late final _metadata = MetadataReconciler(api, workspace, state, _failure);
  Map<String, SyncMetadataAttention> get metadataAttention =>
      Map.unmodifiable(_metadata.attention);
  Map<String, MetadataLimit> get vocabularyAttention =>
      Map.unmodifiable(_metadata.vocabularyAttention);
  Set<String> get metadataWaitingSkillIds =>
      Set.unmodifiable(_metadata.waitingSkillIds);
  bool get metadataUnavailable => _metadata.supported == false;

  Future<void> rebaselineTagEligibility() => _metadata.rebaseline();

  Future<SyncOutcome> resolveNoteConflict(
    String skillId, {
    required int expectedVersion,
    required String? expectedLocalNote,
    required String? value,
  }) async {
    final link = await _link(skillId);
    if (link == null) return const SkillDeviceOnly();
    return _metadata.resolve(
      link,
      expectedVersion: expectedVersion,
      expectedLocalNote: expectedLocalNote,
      value: value,
    );
  }

  final _outcomes = <String, SyncOutcome>{};
  Map<String, SyncOutcome> get outcomes => Map.unmodifiable(_outcomes);
  SyncAccountCondition? _accountCondition;

  /// Account condition observed by the latest check, even without a Skill link.
  SyncAccountCondition? get accountCondition => _accountCondition;
  Duration? _retryAfter;

  Future<SyncOutcome> startSyncing(String skillId) async {
    final old = (await state.links())
        .where((l) => l.managedSkillId == skillId)
        .firstOrNull;
    final link = old ?? SyncLink(managedSkillId: skillId, clientKey: _uuid());
    if (old == null) await state.put(link);
    final outcome = _record(skillId, await _reconcile(link));
    if (outcome is SkillSynced) await _syncSingleSkillMetadata(skillId);
    return outcome;
  }

  Future<SyncOutcome> stopSyncing(String skillId) async {
    final link = await _link(skillId);
    if (link?.lineageId == null) {
      await _unlink(skillId, link?.lineageId);
      return _record(skillId, const SkillDeviceOnly());
    }
    final result = await api.stop(link!.lineageId!);
    if (result is CloudApiSuccess<Lineage> || result is ApiNotFound) {
      await _unlink(skillId, link.lineageId);
      return _record(skillId, const SkillDeviceOnly());
    }
    if (result is ApiLineageEnded && result.lineage != null) {
      return _record(skillId, await _reconcile(link, remote: result.lineage));
    }
    return _record(skillId, _failure(result));
  }

  Future<FeedCheckResult> checkLocalChanges() async {
    _retryAfter = null;
    _accountCondition = null;
    _metadata.throttled = false;
    final changes = await workspace.inspectCommittedChanges(
      await state.workspaceCursor(),
    );
    var success = true;
    for (final link in await state.links()) {
      if (!changes.skillIds.contains(link.managedSkillId) &&
          !link.uploadBlockedByQuota &&
          (link.clientKey == null || link.attentionAttempt != null)) {
        // Links written before Source Epochs were recorded need a local baseline.
        if (link.sourceEpoch == null && link.lineageId != null) {
          final current = await workspace.inspectRevisionSelections(
            link.managedSkillId,
          );
          if (current?.sourceEpoch case final epoch?) {
            await state.put(
              SyncLink(
                managedSkillId: link.managedSkillId,
                lineageId: link.lineageId,
                clientKey: link.clientKey,
                version: link.version,
                generation: link.generation,
                effective: link.effective,
                attentionAttempt: link.attentionAttempt,
                sourceEpoch: epoch,
              ),
            );
          }
        }
        continue;
      }
      final result = _record(link.managedSkillId, await _reconcile(link));
      success = _settled(result) && success;
    }
    final baselines = (await state.metadataState()).lineages;
    final links = (await state.links())
        .where(
          (link) =>
              changes.skillIds.contains(link.managedSkillId) ||
              _metadata.waitingSkillIds.contains(link.managedSkillId) ||
              baselines[link.lineageId]?.quotaBlocked == true ||
              (link.effective != null &&
                  link.attentionAttempt == null &&
                  !baselines.containsKey(link.lineageId)),
        )
        .toList();
    final metadataReady =
        _metadata.supported == true &&
        (await state.metadataState()).bootstrapped;
    if (_metadata.supported == null && await state.feedCursor() != null) {
      // On restart, keep local metadata edits discoverable until the first
      // Feed Check establishes whether this service supports metadata.
      return success
          ? FeedCheckResult.success(retryAfter: _retryAfter)
          : FeedCheckResult.failure(retryAfter: _retryAfter);
    }
    if (metadataReady && _retryAfter == null) {
      final settled = await _metadata.syncBatch(
        links,
        checkVocabulary:
            changes.vocabularyChanged ||
            vocabularyAttention.containsValue(MetadataLimit.vocabulary),
      );
      success = settled && success;
    }
    if (success && (!(_metadata.supported == true) || metadataReady)) {
      await state.setWorkspaceCursor(changes.cursor);
    }
    return success
        ? FeedCheckResult.success(retryAfter: _retryAfter)
        : FeedCheckResult.failure(retryAfter: _retryAfter);
  }

  Future<FeedCheckResult> feedCheck() async {
    _retryAfter = null;
    _accountCondition = null;
    _metadata.throttled = false;
    var success = true;
    final checked = <String>{};
    for (final pending in (await state.links()).where(
      (l) => l.clientKey != null && l.attentionAttempt == null,
    )) {
      checked.add(pending.managedSkillId);
      success =
          _settled(
            _record(pending.managedSkillId, await _reconcile(pending)),
          ) &&
          success;
    }
    if (await state.feedCursor() == null) {
      final result = await _bootstrap();
      if (!result.completed) {
        return result._accountCondition != null && success
            ? FeedCheckResult.success(retryAfter: _retryAfter)
            : FeedCheckResult.failure(retryAfter: _retryAfter);
      }
    } else {
      final support = await _probeMetadata();
      if (support is ApiUnavailable && support.retryAfter != null) {
        return FeedCheckResult.failure(retryAfter: _retryAfter);
      }
      if (support is ApiUnavailable) success = false;
      if (_metadata.supported == true &&
          !(await state.metadataState()).bootstrapped) {
        final initialized = await _bootstrap(metadataOnly: true);
        success = initialized.completed && success;
        if (_metadata.throttled) {
          return FeedCheckResult.failure(retryAfter: _retryAfter);
        }
      } else if (support is CloudApiSuccess<TagVocabulary>) {
        final rebuilt = await _metadata.syncBatch([]);
        success = rebuilt && success;
        if (_metadata.throttled) {
          return FeedCheckResult.failure(retryAfter: _retryAfter);
        }
      }
    }
    while (true) {
      final result = await api.checkFeed(after: await state.feedCursor());
      if (result is ApiCursorExpired) {
        final reset = await _bootstrap(reset: true);
        success =
            (reset.completed || reset._accountCondition != null) && success;
        break;
      }
      if (result is! CloudApiSuccess<FeedPage>) {
        success = _settled(_failure(result)) && success;
        return success
            ? FeedCheckResult.success(retryAfter: _retryAfter)
            : FeedCheckResult.failure(retryAfter: _retryAfter);
      }
      _retryAfter = result.retryAfter ?? _retryAfter;
      final page = result.value;
      var pageSettled = true;
      final newLinks = <String>{};
      for (final entry in page.entries) {
        if (!entry.isLineage || (await state.exclusions()).contains(entry.id)) {
          continue;
        }
        final link = (await state.links())
            .where((l) => l.lineageId == entry.id)
            .firstOrNull;
        if (link != null && entry.version <= link.version) continue;
        final SyncOutcome outcome;
        var outcomeId = link?.managedSkillId ?? entry.id;
        if (link != null) {
          checked.add(link.managedSkillId);
          outcome = await _reconcile(
            link,
            skipUnchangedAttention:
                _outcomes[link.managedSkillId] is! WaitingToUpload,
          );
        } else {
          final remote = await api.readLineage(entry.id);
          if (remote is ApiNotFound) continue;
          if (remote is CloudApiSuccess<Lineage>) {
            final materialized = await _materialize(remote.value);
            outcome = materialized.outcome;
            outcomeId = materialized.managedSkillId ?? outcomeId;
            if (materialized.managedSkillId != null) newLinks.add(entry.id);
          } else {
            outcome = _failure(remote);
          }
        }
        _record(outcomeId, outcome);
        pageSettled = _settled(outcome) && pageSettled;
      }
      if (_metadata.supported == true &&
          (await state.metadataState()).bootstrapped) {
        final versions = (await state.metadataState()).lineages;
        final metadataIds = {
          ...newLinks,
          for (final entry in page.entries)
            if (entry.isMetadata &&
                entry.version > (versions[entry.id]?.observedVersion ?? -1))
              entry.id,
        };
        final links = (await state.links())
            .where((link) => metadataIds.contains(link.lineageId))
            .toList();
        if (links.isNotEmpty ||
            page.entries.any((entry) => entry.isTagVocabulary)) {
          final metadataSettled = await _metadata.syncBatch(
            links,
            checkVocabulary: page.entries.any((entry) => entry.isTagVocabulary),
          );
          pageSettled = metadataSettled && pageSettled;
        }
      }
      success = pageSettled && success;
      if (!pageSettled) break;
      await state.setFeedCursor(page.cursor);
      if (!page.more) break;
    }
    for (final link in await state.links()) {
      if (link.attentionAttempt == null ||
          checked.contains(link.managedSkillId)) {
        continue;
      }
      final result = _record(
        link.managedSkillId,
        await _reconcile(
          link,
          skipUnchangedAttention:
              _outcomes[link.managedSkillId] is! WaitingToUpload,
        ),
      );
      success = _settled(result) && success;
    }
    return success
        ? FeedCheckResult.success(retryAfter: _retryAfter)
        : FeedCheckResult.failure(retryAfter: _retryAfter);
  }

  Future<SyncOutcome> reconcileSkill(String managedSkillId) async {
    final link = await _link(managedSkillId);
    if (link == null) return const SkillDeviceOnly();
    final outcome = _record(managedSkillId, await _reconcile(link));
    await _syncSingleSkillMetadata(managedSkillId);
    return outcome;
  }

  Future<void> _syncSingleSkillMetadata(String skillId) async {
    if (_metadata.supported == null) await _probeMetadata();
    final link = await _link(skillId);
    if (_metadata.supported == true && link?.lineageId != null) {
      await _metadata.syncBatch([link!]);
    }
  }

  Future<void> _unlink(String localId, String? lineageId) async {
    await state.unlink(localId);
    await _metadata.forget(localId, lineageId);
  }

  Future<CloudApiResult<TagVocabulary>?> _probeMetadata() async {
    if (_metadata.supported == true) return null;
    final result = await _metadata.probe();
    if (result is CloudApiSuccess<TagVocabulary>) {
      await _metadata.restoreAttention();
    } else if (result is! ApiNotFound) {
      _failure(result);
      if (result is ApiUnavailable) _metadata.waitForLinks(await state.links());
    }
    return result;
  }

  Future<SyncOutcome> _reconcile(
    SyncLink initial, {
    Lineage? remote,
    bool skipUnchangedAttention = false,
  }) async {
    var link = initial;
    for (var attempt = 0; attempt < 3; attempt++) {
      var local = await workspace.inspectRevisionSelections(
        link.managedSkillId,
      );
      if (link.lineageId == null) {
        if (local == null) {
          await _unlink(link.managedSkillId, link.lineageId);
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
          if (link.clientKey != null) {
            link = await _clearPendingLineage(link);
            continue;
          }
          return _rememberAttention(
            link,
            link.version,
            local,
            const SyncNeedsAttention(AttentionReason.missingAfterReset),
          );
        }
        if (read is! CloudApiSuccess<Lineage>) return _failure(read);
        remote = read.value;
      }
      final previous = link.attentionAttempt;
      final localSourceReplaced =
          link.sourceEpoch != null &&
          local?.sourceEpoch != null &&
          local!.sourceEpoch != link.sourceEpoch;
      if (skipUnchangedAttention &&
          previous != null &&
          !localSourceReplaced &&
          previous.outcome.reason != AttentionReason.missingAfterReset &&
          remote.version == previous.version &&
          local?.effective == previous.effective) {
        return previous.outcome;
      }
      if (remote.state == LineageState.stopped) {
        await _unlink(link.managedSkillId, link.lineageId);
        return const SkillDeviceOnly();
      }
      if (remote.state == LineageState.removed) {
        await _metadata.forget(link.managedSkillId, link.lineageId);
        if (local != null) {
          final applied = await workspace.remove(
            managedSkillId: local.id,
            expectedEffective: local.effective,
            expectedSourceEpoch: local.sourceEpoch,
          );
          if (applied is WorkspaceDraftRequired) {
            return _rememberAttention(
              link,
              remote.version,
              local,
              const SyncNeedsAttention(AttentionReason.removedWithDraft),
            );
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
        await _unlink(link.managedSkillId, link.lineageId);
        return const SkillRemoved();
      }
      if (local == null) {
        final removed = await api.remove(remote.id);
        if (removed is! CloudApiSuccess<Lineage> && removed is! ApiNotFound) {
          return _failure(removed);
        }
        await _unlink(link.managedSkillId, link.lineageId);
        return const SkillRemoved();
      }
      final source = PortableSource.fromJson(remote.source), head = remote.head;
      final newerGeneration = remote.generation > link.generation;
      // A new remote Generation with our changed local epoch and matching
      // bytes can acknowledge a Generation change whose response was lost.
      if (head != null &&
          (newerGeneration ? localSourceReplaced : !localSourceReplaced) &&
          local.source.sameSourceAs(source) &&
          local.effective == head.effective &&
          local.upstream == head.upstream) {
        await _remember(link, remote, local.sourceEpoch);
        return const SkillSynced();
      }
      if (newerGeneration) {
        if (local.effective != link.effective || localSourceReplaced) {
          return _rememberAttention(
            link,
            remote.version,
            local,
            const SyncNeedsAttention(
              AttentionReason.sourceReplacedWithLocalChanges,
            ),
          );
        }
        final outcome = await _replace(link, remote, local);
        return outcome is SyncNeedsAttention
            ? _rememberAttention(link, remote.version, local, outcome)
            : outcome;
      }
      final sourceChanged =
          !local.source.sameSourceAs(source) || localSourceReplaced;
      if (head != null && !sourceChanged) {
        final applied = await _download(
          remote,
          (path) => workspace.applyContent(
            managedSkillId: local!.id,
            expectedEffective: local.effective,
            expectedSourceEpoch: local.sourceEpoch,
            effective: head.effective,
            upstream: head.upstream,
            packPath: path,
          ),
        );
        if (applied.error != null) return applied.error!;
        switch (applied.value!) {
          case WorkspaceDraftRequired():
            return _rememberAttention(
              link,
              remote.version,
              local,
              const SyncNeedsAttention(AttentionReason.incomingDraft),
            );
          case WorkspaceConflicted():
            return _rememberAttention(
              link,
              remote.version,
              local,
              SyncNeedsAttention(
                AttentionReason.syncMergeConflict,
                deviceName: head.deviceName,
              ),
            );
          case WorkspaceApplyFailed(code: WorkspaceFailureCode.staleSnapshot):
            remote = null;
            continue;
          case WorkspaceFastForwarded():
            await _remember(link, remote, local.sourceEpoch);
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
          await _remember(link, remote, local.sourceEpoch);
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
          await _remember(link, value, local.sourceEpoch);
          return const SkillSynced();
        case ApiStaleHead(:final lineage):
          remote = lineage;
        case ApiWrongGeneration(:final lineage):
          remote = lineage;
        case ApiLineageEnded(:final lineage):
          remote = lineage;
        case ApiPackMissing():
          remote = null;
        case ApiNotFound():
          if (link.clientKey != null) {
            link = await _clearPendingLineage(link);
          }
          remote = null;
        default:
          final result = _failure(uploaded);
          if (uploaded is ApiStorageLimitReached &&
              !link.uploadBlockedByQuota) {
            await state.put(
              SyncLink(
                managedSkillId: link.managedSkillId,
                lineageId: link.lineageId,
                clientKey: link.clientKey,
                version: link.version,
                generation: link.generation,
                effective: link.effective,
                sourceEpoch: link.sourceEpoch,
                uploadBlockedByQuota: true,
              ),
            );
          }
          return result is SyncNeedsAttention
              ? _rememberAttention(link, remote.version, local, result)
              : result;
      }
    }
    return const WaitingToUpload();
  }

  Future<SyncLink> _clearPendingLineage(SyncLink link) async {
    await _metadata.forget(link.managedSkillId, link.lineageId);
    final pending = SyncLink(
      managedSkillId: link.managedSkillId,
      clientKey: link.clientKey,
    );
    await state.put(pending);
    return pending;
  }

  Future<SyncNeedsAttention> _rememberAttention(
    SyncLink link,
    int version,
    WorkspaceSkill? local,
    SyncNeedsAttention outcome,
  ) async {
    final attempt = link.attentionAttempt;
    if (attempt?.version != version ||
        attempt?.effective != local?.effective ||
        attempt?.outcome.reason != outcome.reason ||
        attempt?.outcome.deviceName != outcome.deviceName ||
        attempt?.outcome.occupant != outcome.occupant) {
      await state.put(
        SyncLink(
          managedSkillId: link.managedSkillId,
          lineageId: link.lineageId,
          clientKey: link.clientKey,
          version: link.version,
          generation: link.generation,
          effective: link.effective,
          sourceEpoch: link.sourceEpoch,
          attentionAttempt: (
            version: version,
            effective: local?.effective,
            outcome: outcome,
          ),
        ),
      );
    }
    return outcome;
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
          !current.source.sameSourceAs(local.source) ||
          current.sourceEpoch != local.sourceEpoch ||
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

  Future<void> _remember(SyncLink link, Lineage remote, String? sourceEpoch) =>
      state.put(
        SyncLink(
          managedSkillId: link.managedSkillId,
          lineageId: remote.id,
          version: remote.version,
          generation: remote.generation,
          effective: remote.head?.effective,
          sourceEpoch: sourceEpoch,
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
      _retryAfter = result.retryAfter ?? _retryAfter;
      if (result.code == CloudFailureCode.protocol) {
        throw StateError('cloud_protocol');
      }
      return WaitingToUpload(retryAfter: result.retryAfter);
    }
    if (result is ApiSignInRequired || result is ApiStorageLimitReached) {
      final outcome = SyncAccountCondition(result as CloudApiError);
      if (_accountCondition?.condition is! ApiSignInRequired) {
        _accountCondition = outcome;
      }
      return outcome;
    }
    throw StateError('cloud_protocol');
  }

  Never _workspaceDefect() => throw StateError('cloud_workspace_contract');
  bool _settled(SyncOutcome result) => result is! WaitingToUpload;
  Future<String> _scratch() async {
    await Directory(scratchDirectory).create(recursive: true);
    return '$scratchDirectory/${_uuid()}.pack';
  }

  Future<SyncBootstrap> bootstrap({bool reset = false}) {
    _retryAfter = null;
    _accountCondition = null;
    _metadata.throttled = false;
    return _bootstrap(reset: reset);
  }

  Future<SyncBootstrap> _bootstrap({
    bool reset = false,
    bool metadataOnly = false,
  }) async {
    final support = await _probeMetadata();
    if (support is ApiUnavailable && support.retryAfter != null) {
      return SyncBootstrap._unavailable(null, retryAfter: _retryAfter);
    }
    if (support is ApiSignInRequired) {
      return SyncBootstrap._unavailable(_accountCondition);
    }
    final includeMetadata = _metadata.supported == true;
    final library = <Lineage>[];
    final lineageMetadata = <String, LineageMetadata>{};
    TagVocabulary? vocabulary;
    String? cursor, feedCursor;
    var restarted = false;
    do {
      final response = await api.listLibrary(
        cursor: cursor,
        includeMetadata: includeMetadata,
      );
      if (response is ApiCursorExpired && !restarted) {
        restarted = true;
        library.clear();
        lineageMetadata.clear();
        vocabulary = null;
        cursor = feedCursor = null;
        continue;
      }
      if (response is! CloudApiSuccess<LibraryPage>) {
        if (response is ApiCursorExpired) {
          return const SyncBootstrap._unavailable(null);
        }
        final outcome = _failure(response);
        if (includeMetadata && response is ApiUnavailable) {
          _metadata.waitForLinks(await state.links());
        }
        return SyncBootstrap._unavailable(
          outcome is SyncAccountCondition ? outcome : null,
          retryAfter: _retryAfter,
        );
      }
      if (feedCursor != null && feedCursor != response.value.feedCursor) {
        throw StateError('cloud_protocol');
      }
      feedCursor = response.value.feedCursor;
      library.addAll(response.value.lineages);
      for (final metadata
          in response.value.metadata ?? const <LineageMetadata>[]) {
        lineageMetadata[metadata.lineageId] = metadata;
      }
      vocabulary ??= response.value.tagVocabulary;
      cursor = response.value.next;
      if (cursor == null) break;
    } while (true);
    final results = <String, SyncOutcome>{}, installed = <String>{};
    var completed = true;
    for (final remote in metadataOnly ? const <Lineage>[] : library) {
      if ((await state.exclusions()).contains(remote.id)) continue;
      final result = await _materialize(remote);
      results[remote.id] = result.outcome;
      _record(result.managedSkillId ?? remote.id, result.outcome);
      if (result.installed != null) installed.add(result.installed!);
      if (!_settled(result.outcome)) completed = false;
    }
    if (includeMetadata) {
      final links = (await state.links())
          .where((link) => lineageMetadata.containsKey(link.lineageId))
          .toList();
      final metadataSettled = await _metadata.syncBatch(
        links,
        observed: lineageMetadata,
        vocabulary: vocabulary,
      );
      if (metadataSettled && _metadata.supported == true) {
        final saved = await state.metadataState();
        if (!saved.bootstrapped) {
          await state.setMetadataState(saved.copyWith(bootstrapped: true));
        }
      }
      completed = metadataSettled && completed;
    }
    if (reset) {
      final present = library.map((l) => l.id).toSet();
      for (final link in await state.links()) {
        if (link.lineageId != null && !present.contains(link.lineageId)) {
          await _metadata.forget(link.managedSkillId, link.lineageId);
          final outcome = link.clientKey != null
              ? await _reconcile(link)
              : await _rememberAttention(
                  link,
                  link.version,
                  await workspace.inspectRevisionSelections(
                    link.managedSkillId,
                  ),
                  const SyncNeedsAttention(AttentionReason.missingAfterReset),
                );
          results[link.lineageId!] = outcome;
          _record(link.managedSkillId, outcome);
          completed = _settled(outcome) && completed;
        }
      }
    }
    if (completed && !metadataOnly) await state.setFeedCursor(feedCursor);
    return SyncBootstrap(
      installedSkillIds: installed,
      outcomes: results,
      completed: completed,
      retryAfter: _retryAfter,
    );
  }

  Future<({SyncOutcome outcome, String? installed, String? managedSkillId})>
  _materialize(Lineage remote) async {
    if (remote.state != LineageState.live || remote.head == null) {
      return (
        outcome: const SkillDeviceOnly(),
        installed: null,
        managedSkillId: null,
      );
    }
    final linked = (await state.links())
        .where((l) => l.lineageId == remote.id)
        .firstOrNull;
    if (linked != null) {
      return (
        outcome: await _reconcile(
          linked,
          remote: remote,
          skipUnchangedAttention:
              _outcomes[linked.managedSkillId] is! WaitingToUpload,
        ),
        installed: null,
        managedSkillId: linked.managedSkillId,
      );
    }
    final source = PortableSource.fromJson(remote.source), head = remote.head!;
    final existing = (await workspace.listSkills())
        .where(
          (s) =>
              s.source.sameSourceAs(source) &&
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
          managedSkillId: null,
        );
      }
      final link = SyncLink(
        managedSkillId: existing.id,
        lineageId: remote.id,
        generation: remote.generation,
      );
      await state.put(link);
      return (
        outcome: await _reconcile(link, remote: remote),
        installed: null,
        managedSkillId: existing.id,
      );
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
      return (outcome: applied.error!, installed: null, managedSkillId: null);
    }
    if (applied.value case WorkspaceSlotOccupied(:final occupant)) {
      return (
        outcome: SyncNeedsAttention(
          AttentionReason.slotOccupied,
          occupant: occupant,
        ),
        installed: null,
        managedSkillId: null,
      );
    }
    if (applied.value case WorkspaceInstalled(
      :final managedSkillId,
      :final sourceEpoch,
    )) {
      if (_metadata.supported == true) {
        await _metadata.installed(managedSkillId, remote.id);
      }
      await _remember(
        SyncLink(managedSkillId: managedSkillId),
        remote,
        sourceEpoch,
      );
      return (
        outcome: const SkillSynced(),
        installed: managedSkillId,
        managedSkillId: managedSkillId,
      );
    }
    _workspaceDefect();
  }

  Future<void> exclude(String lineageId) async {
    await state.setExcluded(lineageId, true);
    for (final link in (await state.links()).where(
      (l) => l.lineageId == lineageId,
    )) {
      await _unlink(link.managedSkillId, link.lineageId);
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
      await _unlink(skillId, link?.lineageId);
    }
    return _record(skillId, const SkillDeviceOnly());
  }

  Future<SyncOutcome> removeMissingLocally(String skillId) async {
    final local = await workspace.inspectRevisionSelections(skillId);
    if (local != null) {
      final applied = await workspace.remove(
        managedSkillId: skillId,
        expectedEffective: local.effective,
        expectedSourceEpoch: local.sourceEpoch,
      );
      if (applied case WorkspaceApplyFailed(
        code: WorkspaceFailureCode.staleSnapshot,
      )) {
        throw const FormatException('cloud_confirmation_stale');
      }
      if (applied is WorkspaceDraftRequired) {
        return _record(
          skillId,
          const SyncNeedsAttention(AttentionReason.removedWithDraft),
        );
      }
      if (applied is! WorkspaceRemoved) _workspaceDefect();
    }
    await _unlink(skillId, (await _link(skillId))?.lineageId);
    return _record(skillId, const SkillRemoved());
  }

  Future<SyncOutcome> uploadAsNewLineage(String skillId) async {
    await _unlink(skillId, (await _link(skillId))?.lineageId);
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
    if (result is ApiNotFound) {
      return _record(
        skillId,
        await _rememberAttention(
          link,
          link.version,
          local,
          const SyncNeedsAttention(AttentionReason.missingAfterReset),
        ),
      );
    }
    if (result is! CloudApiSuccess<Lineage>) return _failure(result);
    final outcome = await _replace(link, result.value, local);
    if (outcome is SyncNeedsAttention) {
      await _rememberAttention(link, result.value.version, local, outcome);
    }
    return _record(skillId, outcome);
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
    if (result is ApiNotFound) {
      return const SyncNeedsAttention(AttentionReason.missingAfterReset);
    }
    if (result is! CloudApiSuccess<Lineage>) return _failure(result);
    if (result.value.state != LineageState.live || result.value.head == null) {
      return const SkillDeviceOnly();
    }
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
      return _reconcile(link, remote: remote);
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
            expectedSourceEpoch:
                remote.generation > link.generation && link.effective != null
                ? local.sourceEpoch
                : null,
          ),
        );
    if (applied.error != null) return applied.error!;
    switch (applied.value!) {
      case WorkspaceSourceReplaced(:final sourceEpoch):
        await _remember(link, remote, sourceEpoch);
        return const SkillSynced();
      case WorkspaceNoChange(:final sourceEpoch):
        await _remember(link, remote, sourceEpoch ?? local.sourceEpoch);
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
