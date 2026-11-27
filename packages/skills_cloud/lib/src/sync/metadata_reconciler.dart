import 'dart:convert';

import '../api/cloud_api.dart';
import '../api/cloud_result.dart';
import '../api/metadata_values.dart';
import '../sign_in/cloud_sign_in.dart';
import 'sync_metadata_state.dart';
import 'sync_outcome.dart';
import 'sync_state_store.dart';
import 'sync_workspace.dart';

/// Reconciles metadata independently of the content result for a Lineage.
final class MetadataReconciler {
  MetadataReconciler(this.api, this.workspace, this.store, this.onFailure);

  final CloudApi api;
  final SyncWorkspace workspace;
  final SyncStateStore store;
  final SyncOutcome Function(CloudApiResult<Object?>) onFailure;
  final attention = <String, SyncMetadataAttention>{};
  final vocabularyAttention = <String, MetadataLimit>{};
  final waitingSkillIds = <String>{};
  bool? supported;
  bool throttled = false;

  Future<void> rebaseline() async {
    final local = await workspace.inspectMetadata();
    final state = await store.metadataState();
    final mapped = state.tags.values.map((tag) => tag.localId).toSet();
    final localTagIds = local.tags.keys.toSet();
    await store.setMetadataState(
      state.copyWith(
        knownTagIds: localTagIds,
        eligibleTagIds: state.eligibleTagIds.intersection(localTagIds),
        lineages: {
          for (final entry in state.lineages.entries)
            entry.key: entry.value.assignments == null
                ? entry.value
                : entry.value.copyWith(
                    localOnlyTagIds: local.skills[entry.value.localId]?.tagIds
                        .difference(mapped),
                  ),
        },
      ),
    );
  }

  Future<void> markUnsupported() async {
    supported = false;
    waitingSkillIds.clear();
    final state = await store.metadataState();
    if (state.bootstrapped) {
      await store.setMetadataState(state.copyWith(bootstrapped: false));
    }
  }

  Future<CloudApiResult<TagVocabulary>> probe() async {
    final result = await api.readTags();
    if (result is ApiNotFound) await markUnsupported();
    if (result is CloudApiSuccess<TagVocabulary>) supported = true;
    return result;
  }

  Future<void> restoreAttention() async {
    final state = await store.metadataState();
    final local = await workspace.inspectMetadata();
    final linked = {
      for (final link in await store.links())
        if (link.lineageId != null) link.lineageId!: link.managedSkillId,
    };
    for (final baseline in state.lineages.entries) {
      final entry = baseline.value;
      if (linked[baseline.key] != entry.localId) continue;
      final skill = local.skills[entry.localId];
      if (skill == null) continue;
      _showNote(entry.localId, skill.note, entry.note, entry.retainLocalNote);
    }
  }

  Future<void> forget(String localId, String? lineageId) async {
    attention.remove(localId);
    waitingSkillIds.remove(localId);
    if (lineageId == null) return;
    final state = await store.metadataState();
    if (!state.lineages.containsKey(lineageId)) return;
    await store.setMetadataState(
      state.copyWith(lineages: {...state.lineages}..remove(lineageId)),
    );
  }

  Future<void> installed(String localId, String lineageId) async {
    await _remember(
      lineageId,
      SyncMetadataBaseline(
        localId,
        favorite: const CloudFavorite(false, 0),
        note: const CloudNote(null, 0),
        assignments: const {},
      ),
    );
  }

  Future<void> _remember(
    String lineageId,
    SyncMetadataBaseline baseline,
  ) async {
    final state = await store.metadataState();
    await store.setMetadataState(
      state.copyWith(lineages: {...state.lineages, lineageId: baseline}),
    );
  }

  SyncOutcome _failed(CloudApiResult<Object?> result) {
    if (result is ApiUnavailable && result.retryAfter != null) throttled = true;
    return onFailure(result);
  }

  bool _settled(CloudApiResult<Object?> result) =>
      _failed(result) is! WaitingToUpload;

  void waitForLinks(Iterable<SyncLink> links) {
    waitingSkillIds.addAll(
      links
          .where((link) => link.lineageId != null)
          .map((link) => link.managedSkillId),
    );
  }

  Future<bool> syncBatch(
    List<SyncLink> links, {
    Map<String, LineageMetadata> observed = const {},
    TagVocabulary? vocabulary,
    bool checkVocabulary = false,
  }) async {
    if (supported != true) return true;
    if (throttled) {
      waitForLinks(links);
      return false;
    }
    final initial = {...observed};
    final state = await store.metadataState();
    final unavailable = <String>{};
    var settled = true;
    for (final link in links) {
      final id = link.lineageId;
      if (id == null ||
          initial.containsKey(id) ||
          state.lineages[id]?.assignments != null) {
        continue;
      }
      final response = await api.readMetadata(id);
      if (response is CloudApiSuccess<LineageMetadata>) {
        initial[id] = response.value;
      } else if (response is! ApiLineageEnded && response is! ApiNotFound) {
        final readSettled = _settled(response);
        if (!readSettled) waitingSkillIds.add(link.managedSkillId);
        settled = readSettled && settled;
        unavailable.add(id);
        if (throttled) return false;
      }
    }
    final local = await workspace.inspectMetadata();
    final knownTagIds = state.knownTagIds;
    final newTagIds = knownTagIds == null
        ? const <String>{}
        : local.tags.keys.toSet().difference(knownTagIds);
    await markEligible(local, links, initial);
    final updated = await store.metadataState();
    if (checkVocabulary ||
        vocabulary != null ||
        _hasVocabularyDelta(local, updated)) {
      settled = await syncVocabulary(observed: vocabulary) && settled;
      if (throttled) {
        waitForLinks(links);
        return false;
      }
    }
    for (final link in links) {
      final id = link.lineageId;
      if (id == null || unavailable.contains(id)) continue;
      settled =
          await syncSkill(link, observed: initial[id], newTagIds: newTagIds) &&
          settled;
      if (throttled) return false;
    }
    return settled;
  }

  bool _hasVocabularyDelta(
    WorkspaceMetadataSnapshot local,
    SyncMetadataState state,
  ) {
    final mapped = <String>{};
    for (final entry in state.tags.values) {
      mapped.add(entry.localId);
      final current = local.tags[entry.localId];
      if (current == null ||
          current.name != entry.remote.name ||
          current.color != entry.remote.color) {
        return true;
      }
    }
    return !mapped.containsAll(state.eligibleTagIds);
  }

  /// Select old assigned tags only after determining which local assignments
  /// can initialize the cloud. New tag IDs are eligible anywhere in Workspace.
  Future<void> markEligible(
    WorkspaceMetadataSnapshot local,
    List<SyncLink> links,
    Map<String, LineageMetadata> remote,
  ) async {
    final state = await store.metadataState();
    final known = state.knownTagIds ?? local.tags.keys.toSet();
    final eligible = {
      ...state.eligibleTagIds,
      ...local.tags.keys.where((id) => !known.contains(id)),
    }.intersection(local.tags.keys.toSet());
    final mapped = state.tags.values.map((tag) => tag.localId).toSet();
    for (final link in links) {
      final id = link.lineageId;
      final skill = local.skills[link.managedSkillId];
      if (id == null || skill == null) continue;
      final baseline = state.lineages[id];
      final candidates = baseline?.assignments != null
          ? skill.tagIds.difference(baseline!.localOnlyTagIds)
          : remote[id]?.assignmentVersion == 0
          ? skill.tagIds
          : const <String>{};
      eligible.addAll(candidates.difference(mapped));
    }
    final allKnown = local.tags.keys.toSet();
    if (state.knownTagIds != null &&
        _sameSet(known, allKnown) &&
        _sameSet(eligible, state.eligibleTagIds)) {
      return;
    }
    await store.setMetadataState(
      state.copyWith(knownTagIds: allKnown, eligibleTagIds: eligible),
    );
  }

  Future<bool> syncVocabulary({TagVocabulary? observed}) async {
    if (supported != true || throttled) return !throttled;
    if (observed == null) {
      final result = await api.readTags();
      if (result is ApiNotFound) {
        await markUnsupported();
        return true;
      }
      if (result is! CloudApiSuccess<TagVocabulary>) return _settled(result);
      observed = result.value;
    }
    // Endings precede reuse of a normalized name.
    var settled = true;
    var quotaReached = false;
    void onCreateQuota() => quotaReached = true;
    for (final mapping in (await store.metadataState()).tags.values) {
      if (observed.tags.containsKey(mapping.remote.id)) continue;
      final current = await api.readTag(mapping.remote.id);
      if (current is CloudApiSuccess<CloudTag>) {
        // The listing preceded a newer observation. Never delete from it.
        continue;
      }
      final ended = await _settleEndedTag(mapping, current);
      settled = ended && settled;
      if (throttled) return false;
    }
    final remaining = {...observed.tags};
    var staleCycles = 0;
    while (remaining.isNotEmpty) {
      final current = await workspace.inspectMetadata();
      final mappings = (await store.metadataState()).tags;
      final localOwners = {
        for (final entry in mappings.entries)
          if (current.tags[entry.value.localId] case final tag?)
            tag.normalizedName: entry.key,
      };
      final tag = remaining.values.where((tag) {
        final owner = localOwners[tag.normalizedName];
        final mapping = mappings[tag.id];
        final local = current.tags[mapping?.localId];
        final pendingName =
            local != null &&
            local.name != mapping!.remote.name &&
            local.name != tag.name &&
            local.name.runes.length <= 64;
        // Vacate reused names in dependency order. A valid pending local
        // rename can settle first against the server's current Name Version.
        return owner == null || owner == tag.id || pendingName;
      }).firstOrNull;
      if (tag == null) {
        final cycle = _renameCycle(remaining, localOwners);
        if (cycle.isEmpty || staleCycles == 3) return false;
        // A bootstrap projection can be older than the local metadata read.
        final fresh = await api.readTags();
        if (fresh is ApiNotFound) {
          await markUnsupported();
          return true;
        }
        if (fresh is! CloudApiSuccess<TagVocabulary>) return _settled(fresh);
        final names = <String, String>{};
        for (final id in cycle) {
          final mapping = mappings[id]!;
          final latest = fresh.value.tags[id];
          final local = current.tags[mapping.localId]!;
          if (latest == null ||
              latest.nameVersion != remaining[id]!.nameVersion ||
              latest.name != remaining[id]!.name ||
              local.name != mapping.remote.name) {
            return false;
          }
          names[mapping.localId] = latest.name;
          remaining[id] = latest;
        }
        final applied = await workspace.renameTags(
          expectedRevision: current.revision,
          names: names,
        );
        if (_tagStale(applied)) staleCycles++;
        continue;
      }
      remaining.remove(tag.id);
      settled =
          await _syncExistingTag(tag, onCreateQuota: onCreateQuota) && settled;
      if (throttled) return false;
    }
    final state = await store.metadataState();
    final local = await workspace.inspectMetadata();
    final mapped = state.tags.values.map((tag) => tag.localId).toSet();
    for (final id in state.eligibleTagIds) {
      final tag = local.tags[id];
      if (mapped.contains(id) || tag == null) continue;
      if (quotaReached) {
        vocabularyAttention[id] = tag.name.runes.length > 64
            ? MetadataLimit.name
            : MetadataLimit.vocabulary;
        continue;
      }
      settled = await _createTag(id, onQuota: onCreateQuota) && settled;
      if (throttled) return false;
    }
    vocabularyAttention.removeWhere((id, _) => !local.tags.containsKey(id));
    return settled;
  }

  Future<bool> _createTag(String localId, {void Function()? onQuota}) async {
    final start = (await workspace.inspectMetadata()).tags[localId];
    if (start == null) return true;
    if (start.name.runes.length > 64) {
      vocabularyAttention[localId] = MetadataLimit.name;
      return true;
    }
    final response = await api.createTag(
      clientKey: workspace.tagClientKey(localId),
      name: start.name,
      color: start.color,
    );
    if (response is ApiTagDeleted || response is ApiNotFound) {
      for (var attempt = 0; attempt < 3; attempt++) {
        final local = await workspace.inspectMetadata();
        if (local.tags.containsKey(localId)) {
          final applied = await workspace.deleteTag(
            expectedRevision: local.revision,
            localTagId: localId,
          );
          if (_tagStale(applied)) continue;
        }
        vocabularyAttention.remove(localId);
        final state = await store.metadataState();
        await store.setMetadataState(
          state.copyWith(
            eligibleTagIds: {...state.eligibleTagIds}..remove(localId),
          ),
        );
        return true;
      }
      return false;
    }
    if (response is! CloudApiSuccess<CloudTag>) {
      if (response is ApiStorageLimitReached) onQuota?.call();
      return _tagFailure(localId, response);
    }
    final remote = response.value;
    var baseline = _tagValues(remote, name: start.name, color: start.color);
    for (var attempt = 0; attempt < 3; attempt++) {
      final local = await workspace.inspectMetadata();
      final current = local.tags[localId];
      final mapped = (await store.metadataState()).tags[remote.id];
      if (current == null) {
        if (mapped == null) await _mapTag(remote.id, localId, baseline);
        return true;
      }
      final name = current.name == start.name ? remote.name : current.name;
      final color = current.color == start.color ? remote.color : current.color;
      if (mapped != null && mapped.localId != localId) {
        // Multiple local tags can converge through a lost-create alias.
        final merged = await _mergeLocalTag(local, localId, remote, mapped);
        if (merged == null) continue;
        await _mapTag(remote.id, merged, mapped.remote);
        break;
      }
      if (name == current.name && color == current.color) {
        baseline = _tagValues(
          remote,
          name: current.name == start.name ? remote.name : start.name,
          color: current.color == start.color ? remote.color : start.color,
        );
        await _mapTag(remote.id, localId, baseline);
        if (current.name != start.name || current.color != start.color) {
          return _syncExistingTag(remote);
        }
        break;
      }
      final updated = await workspace.updateTag(
        expectedRevision: local.revision,
        localTagId: localId,
        name: name,
        color: color,
      );
      if (_tagStale(updated)) continue;
      final resolved = (updated as WorkspaceTagApplied).localTagId!;
      baseline = _tagValues(
        remote,
        name: current.name == start.name ? remote.name : start.name,
        color: current.color == start.color ? remote.color : start.color,
      );
      await _mapTag(remote.id, resolved, baseline);
      if (current.name != start.name || current.color != start.color) {
        return _syncExistingTag(remote);
      }
      break;
    }
    vocabularyAttention.remove(localId);
    return (await store.metadataState()).tags.containsKey(remote.id);
  }

  Future<bool> _syncExistingTag(
    CloudTag observed, {
    void Function()? onCreateQuota,
  }) async {
    var remote = observed;
    for (var attempt = 0; attempt < 3; attempt++) {
      final state = await store.metadataState();
      final mapping = state.tags[remote.id];
      var local = await workspace.inspectMetadata();
      if (mapping == null) {
        // Give an eligible local tag's creation key a chance to recover a
        // canonical ID before a same-name vocabulary entry claims it.
        final matching = local.tags.values
            .where(
              (tag) =>
                  tag.normalizedName == remote.normalizedName &&
                  state.eligibleTagIds.contains(tag.id) &&
                  !state.tags.values.any(
                    (mapping) => mapping.localId == tag.id,
                  ),
            )
            .firstOrNull;
        if (matching != null) {
          if (!await _createTag(matching.id, onQuota: onCreateQuota)) {
            return false;
          }
          if ((await store.metadataState()).tags.containsKey(remote.id)) {
            return true;
          }
          if (vocabularyAttention.containsKey(matching.id)) return true;
          continue;
        }
        if (_occupiedByMappedTag(remote, state, local)) return false;
        final ensured = await workspace.ensureTag(
          expectedRevision: local.revision,
          name: remote.name,
          color: remote.color,
        );
        if (_tagStale(ensured)) continue;
        final localId = (ensured as WorkspaceTagApplied).localTagId!;
        await _mapTag(remote.id, localId, remote);
        return true;
      }
      if (remote.version < mapping.remote.version) {
        final latest = await api.readTag(remote.id);
        if (latest is! CloudApiSuccess<CloudTag>) {
          return _settleEndedTag(mapping, latest);
        }
        remote = latest.value;
        // A direct read can confirm a lower version after a rollback.
        local = await workspace.inspectMetadata();
      }
      final current = local.tags[mapping.localId];
      if (current == null) {
        final response = await api.deleteTag(
          remote.id,
          expectedVersion: remote.version,
        );
        if (response is ApiStaleFieldVersion && response.current is CloudTag) {
          remote = response.current as CloudTag;
          continue;
        }
        if (response is CloudApiSuccess<String>) {
          return _settleEndedTag(mapping, const ApiTagDeleted());
        }
        return _settleEndedTag(mapping, response);
      }
      final pendingName =
          current.name != mapping.remote.name && current.name != remote.name;
      final pendingColor =
          current.color != mapping.remote.color &&
          current.color != remote.color;
      var nameBlocked = false;
      if (pendingName) {
        if (current.name.runes.length > 64) {
          vocabularyAttention[current.id] = MetadataLimit.name;
          nameBlocked = true;
        } else {
          final response = await api.renameTag(
            remote.id,
            expectedVersion: remote.nameVersion,
            name: current.name,
          );
          if (response is CloudApiSuccess<CloudTag>) {
            final accepted = response.value;
            if (accepted.id != remote.id) {
              return _settleEndedTag(
                mapping,
                ApiTagMerged(accepted.id),
                survivor: accepted,
              );
            }
            await _mapTag(
              remote.id,
              current.id,
              _tagValues(
                accepted,
                name: accepted.name,
                color: mapping.remote.color,
              ),
            );
            vocabularyAttention.remove(current.id);
            remote = accepted;
            continue;
          }
          if (response is ApiStaleFieldVersion &&
              response.current is CloudTag) {
            remote = response.current as CloudTag;
            continue;
          }
          if (response is ApiMetadataTooLarge) {
            vocabularyAttention[current.id] = MetadataLimit.name;
            nameBlocked = true;
          } else {
            return _settleEndedTag(mapping, response);
          }
        }
      } else {
        vocabularyAttention.remove(current.id);
      }
      if (pendingColor) {
        final response = await api.recolorTag(
          remote.id,
          expectedVersion: remote.colorVersion,
          color: current.color,
        );
        if (response is CloudApiSuccess<CloudTag>) {
          final accepted = response.value;
          await _mapTag(
            remote.id,
            current.id,
            _tagValues(
              accepted,
              name: mapping.remote.name,
              color: accepted.color,
            ),
          );
          remote = accepted;
          continue;
        }
        if (response is ApiStaleFieldVersion && response.current is CloudTag) {
          remote = response.current as CloudTag;
          continue;
        }
        return _settleEndedTag(mapping, response);
      }
      final intendedName = nameBlocked ? current.name : remote.name;
      var localId = current.id;
      if (current.name != intendedName || current.color != remote.color) {
        if (current.name != intendedName &&
            _occupiedByMappedTag(remote, state, local)) {
          return false;
        }
        final applied = await workspace.updateTag(
          expectedRevision: local.revision,
          localTagId: current.id,
          name: intendedName,
          color: remote.color,
        );
        if (_tagStale(applied)) continue;
        localId = (applied as WorkspaceTagApplied).localTagId!;
      }
      await _mapTag(
        remote.id,
        localId,
        nameBlocked
            ? _tagValues(remote, name: mapping.remote.name, color: remote.color)
            : remote,
      );
      return true;
    }
    return false;
  }

  bool _occupiedByMappedTag(
    CloudTag remote,
    SyncMetadataState state,
    WorkspaceMetadataSnapshot snapshot,
  ) => state.tags.entries.any(
    (entry) =>
        entry.key != remote.id &&
        snapshot.tags[entry.value.localId]?.normalizedName ==
            remote.normalizedName,
  );

  Future<String?> _mergeLocalTag(
    WorkspaceMetadataSnapshot snapshot,
    String localId,
    CloudTag survivor,
    SyncTagBaseline? mapping,
  ) async {
    final mapped = snapshot.tags[mapping?.localId];
    if (mapping != null && mapped == null) {
      // Preserve a pending local deletion of the canonical tag.
      if (snapshot.tags.containsKey(localId)) {
        final removed = await workspace.deleteTag(
          expectedRevision: snapshot.revision,
          localTagId: localId,
        );
        if (_tagStale(removed)) return null;
      }
      return mapping.localId;
    }
    final name = mapped?.name ?? survivor.name;
    final color = mapped == null ? survivor.color : mapped.color;
    final result = snapshot.tags.containsKey(localId)
        ? await workspace.updateTag(
            expectedRevision: snapshot.revision,
            localTagId: localId,
            name: name,
            color: color,
          )
        : await workspace.ensureTag(
            expectedRevision: snapshot.revision,
            name: name,
            color: color,
          );
    return _tagStale(result)
        ? null
        : (result as WorkspaceTagApplied).localTagId!;
  }

  Future<bool> _settleEndedTag(
    SyncTagBaseline old,
    CloudApiResult<Object?> result, {
    CloudTag? survivor,
  }) async {
    final replacement = result is ApiTagMerged ? result.replacementTagId : null;
    if (replacement != null && survivor == null) {
      final read = await api.readTag(replacement);
      if (read is CloudApiSuccess<CloudTag>) {
        survivor = read.value;
      } else if (read is! ApiTagDeleted && read is! ApiNotFound) {
        // Recheck the canonical chain on the next bounded reconciliation.
        return read is ApiTagMerged ? false : _tagFailure(old.localId, read);
      }
    } else if (replacement == null &&
        result is! ApiTagDeleted &&
        result is! ApiNotFound) {
      return _tagFailure(old.localId, result);
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      final local = await workspace.inspectMetadata();
      final state = await store.metadataState();
      final survivorMapping = state.tags[survivor?.id];
      String? survivorLocalId;
      if (survivor != null) {
        survivorLocalId = await _mergeLocalTag(
          local,
          old.localId,
          survivor,
          survivorMapping,
        );
        if (survivorLocalId == null) continue;
      } else if (local.tags.containsKey(old.localId)) {
        final deleted = await workspace.deleteTag(
          expectedRevision: local.revision,
          localTagId: old.localId,
        );
        if (_tagStale(deleted)) continue;
      }
      final tags = {...state.tags}..remove(old.remote.id);
      if (survivor != null) {
        tags[survivor.id] = SyncTagBaseline(
          survivorLocalId!,
          survivorMapping?.remote ?? survivor,
        );
      }
      final lineages = <String, SyncMetadataBaseline>{};
      for (final entry in state.lineages.entries) {
        final baseline = entry.value;
        final assignments = baseline.assignments;
        final previous = assignments?[old.remote.id];
        if (assignments == null || previous == null) {
          lineages[entry.key] = baseline;
          continue;
        }
        final revised = {...assignments}..remove(old.remote.id);
        if (survivor != null &&
            previous.assigned &&
            revised[survivor.id]?.assigned != true) {
          revised[survivor.id] = CloudAssignment(survivor.id, true, 0);
        }
        lineages[entry.key] = baseline.copyWith(assignments: revised);
      }
      await store.setMetadataState(
        state.copyWith(
          tags: tags,
          lineages: lineages,
          knownTagIds: {...?state.knownTagIds, ?survivorLocalId},
          eligibleTagIds: {...state.eligibleTagIds}..remove(old.localId),
        ),
      );
      vocabularyAttention.remove(old.localId);
      return true;
    }
    return false;
  }

  Future<void> _mapTag(String id, String localId, CloudTag remote) async {
    final state = await store.metadataState();
    final previous = state.tags[id];
    if (previous != null &&
        previous.localId == localId &&
        state.knownTagIds?.contains(localId) == true &&
        previous.remote.id == remote.id &&
        previous.remote.version == remote.version &&
        previous.remote.nameVersion == remote.nameVersion &&
        previous.remote.colorVersion == remote.colorVersion &&
        previous.remote.name == remote.name &&
        previous.remote.normalizedName == remote.normalizedName &&
        previous.remote.color == remote.color) {
      return;
    }
    await store.setMetadataState(
      state.copyWith(
        tags: {...state.tags, id: SyncTagBaseline(localId, remote)},
        knownTagIds: {...?state.knownTagIds, localId},
      ),
    );
  }

  bool _tagFailure(String localId, CloudApiResult<Object?> result) {
    if (result is ApiMetadataTooLarge || result is ApiStorageLimitReached) {
      vocabularyAttention[localId] = result is ApiMetadataTooLarge
          ? result.field
          : MetadataLimit.vocabulary;
      return true;
    }
    return _settled(result);
  }

  bool _tagStale(WorkspaceTagApply result) {
    if (result is WorkspaceTagApplied) return false;
    if (result case WorkspaceTagApplyFailed(
      code: WorkspaceFailureCode.staleSnapshot,
    )) {
      return true;
    }
    throw StateError('cloud_workspace_contract');
  }

  Future<bool> syncSkill(
    SyncLink link, {
    LineageMetadata? observed,
    Set<String> newTagIds = const {},
  }) async {
    final id = link.lineageId;
    if (id == null || supported != true) return true;
    final settled =
        !throttled && await _syncSkill(link, id, observed, newTagIds);
    if (settled) {
      waitingSkillIds.remove(link.managedSkillId);
    } else {
      waitingSkillIds.add(link.managedSkillId);
    }
    return settled;
  }

  Future<bool> _syncSkill(
    SyncLink link,
    String id,
    LineageMetadata? observed,
    Set<String> newTagIds,
  ) async {
    Set<String>? initialTagIds;
    for (var attempt = 0; attempt < 3; attempt++) {
      final state = await store.metadataState();
      if (observed == null ||
          observed.version < (state.lineages[id]?.observedVersion ?? 0)) {
        final response = await api.readMetadata(id);
        if (response is ApiLineageEnded) {
          await forget(link.managedSkillId, id);
          return true;
        }
        if (response is ApiNotFound) return true;
        if (response is! CloudApiSuccess<LineageMetadata>) {
          return _settled(response);
        }
        observed = response.value;
      }
      if (!state.tags.keys.toSet().containsAll(observed.assignments.keys)) {
        if (!await syncVocabulary()) return false;
        observed = null;
        continue;
      }
      final skillId = link.managedSkillId;
      final local = await workspace.inspectMetadata();
      final skill = local.skills[skillId];
      if (skill == null) return true;
      final tagsAtStart = initialTagIds ??= skill.tagIds;
      final prior = state.lineages[id];
      var baseline = prior?.localId == skillId
          ? prior!
          : SyncMetadataBaseline(skillId);
      var settled = true;
      var quotaBlocked = false;
      var favorite = observed.favorite;
      var keepLocalFavorite = false;
      final wantsFavorite = baseline.favorite == null
          ? favorite.version == 0
          : baseline.favorite!.value != skill.favorite;
      if (wantsFavorite && favorite.value != skill.favorite) {
        final result = await api.writeFavorite(
          id,
          expectedVersion: favorite.version,
          value: skill.favorite,
        );
        if (result is CloudApiSuccess<CloudFavorite>) {
          favorite = result.value;
          baseline = baseline.copyWith(favorite: favorite);
          await _remember(id, baseline);
        } else if (result is ApiStaleFieldVersion) {
          observed = null;
          continue;
        } else if (result is ApiNotFound || result is ApiLineageEnded) {
          return true;
        } else {
          quotaBlocked = result is ApiStorageLimitReached;
          settled = _settled(result);
          keepLocalFavorite = true;
          if (throttled) return false;
        }
      }

      final noteResult = await _syncNote(
        id,
        skillId,
        skill.note,
        observed.note,
        baseline,
      );
      if (noteResult == null) {
        observed = null;
        continue;
      }
      if (noteResult.ended) return true;
      if (throttled) return false;
      settled = noteResult.settled && settled;
      quotaBlocked = noteResult.quotaBlocked || quotaBlocked;
      if (noteResult.accepted) {
        baseline = baseline.copyWith(
          note: noteResult.note,
          retainLocalNote: false,
        );
        await _remember(id, baseline);
      }

      final localToRemote = {
        for (final entry in state.tags.entries) entry.value.localId: entry.key,
      };
      final cloudWinsAssignments =
          baseline.assignments == null && observed.assignmentVersion > 0;
      final localOnly = skill.tagIds.difference(localToRemote.keys.toSet());
      if (cloudWinsAssignments) {
        // Cloud initializes the whole assignment set. Preserve tags assigned
        // during a stale local apply and tags just created on this Device.
        localOnly.removeWhere(
          (id) =>
              tagsAtStart.contains(id) &&
              !newTagIds.contains(id) &&
              state.knownTagIds?.contains(id) != false,
        );
      }
      final desiredTags = {...localOnly};
      final localCloudTags = skill.tagIds
          .map((id) => localToRemote[id])
          .nonNulls
          .toSet();
      final assignmentBaseline = {...?baseline.assignments};
      final tagIds = <String>{
        ...localCloudTags,
        ...observed.assignments.keys,
        ...assignmentBaseline.keys,
      };
      var refresh = false;
      for (final tagId in tagIds) {
        final mapping = state.tags[tagId];
        if (mapping == null) {
          assignmentBaseline.remove(tagId);
          continue;
        }
        var remote =
            observed.assignments[tagId] ??
            CloudAssignment(
              tagId,
              false,
              assignmentBaseline[tagId]?.assigned == false
                  ? assignmentBaseline[tagId]!.version
                  : 0,
            );
        final assignedLocally = localCloudTags.contains(tagId);
        final wantsAssignment = baseline.assignments == null
            ? !cloudWinsAssignments ||
                  newTagIds.contains(mapping.localId) ||
                  assignedLocally != tagsAtStart.contains(mapping.localId)
            : assignedLocally != (assignmentBaseline[tagId]?.assigned ?? false);
        if (wantsAssignment && assignedLocally != remote.assigned) {
          // An absent membership can retain a version after unassignment.
          if (!remote.assigned) {
            final read = await api.readAssignment(id, tagId);
            if (read is CloudApiSuccess<CloudAssignment>) {
              remote = read.value;
            } else if (read is ApiTagMerged || read is ApiTagDeleted) {
              if (!await syncVocabulary()) return false;
              refresh = true;
              break;
            } else if (read is ApiNotFound || read is ApiLineageEnded) {
              return true;
            } else {
              quotaBlocked = read is ApiStorageLimitReached || quotaBlocked;
              settled = _settled(read) && settled;
              if (throttled) return false;
              if (assignedLocally) desiredTags.add(mapping.localId);
              continue;
            }
          }
          if (assignedLocally != remote.assigned) {
            final now = await workspace.inspectMetadata();
            if (now.revision != local.revision) {
              refresh = true;
              break;
            }
            final result = await api.writeAssignment(
              id,
              tagId,
              expectedVersion: remote.version,
              assigned: assignedLocally,
            );
            if (result is CloudApiSuccess<CloudAssignment>) {
              remote = result.value;
              // Persist only acknowledged writes before local CAS. Other
              // assignment observations still await the guarded local apply.
              if (!cloudWinsAssignments) {
                baseline = baseline.copyWith(
                  assignments: {...?baseline.assignments, tagId: remote},
                );
                await _remember(id, baseline);
              }
            } else if (result is ApiStaleFieldVersion) {
              refresh = true;
              break;
            } else if (result is ApiTagDeleted || result is ApiTagMerged) {
              if (!await syncVocabulary()) return false;
              refresh = true;
              break;
            } else if (result is ApiLineageEnded || result is ApiNotFound) {
              return true;
            } else {
              quotaBlocked = result is ApiStorageLimitReached || quotaBlocked;
              settled = _settled(result) && settled;
              if (throttled) return false;
              if (assignedLocally) desiredTags.add(mapping.localId);
              continue;
            }
          }
        }
        assignmentBaseline[tagId] = remote;
        if (remote.assigned) desiredTags.add(mapping.localId);
      }
      if (refresh) {
        observed = null;
        continue;
      }
      final desiredFavorite = keepLocalFavorite
          ? skill.favorite
          : favorite.value;
      final desiredNote = noteResult.keepLocal
          ? skill.note
          : noteResult.note.value;
      if (desiredFavorite != skill.favorite ||
          desiredNote != skill.note ||
          !_sameSet(desiredTags, skill.tagIds)) {
        final applied = await workspace.applyMetadata(
          managedSkillId: skillId,
          expectedRevision: local.revision,
          favorite: desiredFavorite,
          note: desiredNote,
          tagIds: desiredTags,
        );
        if (applied case WorkspaceApplyFailed(
          code: WorkspaceFailureCode.staleSnapshot,
        )) {
          observed = null;
          continue;
        }
        if (applied case WorkspaceApplyFailed(
          code: WorkspaceFailureCode.skillNotFound,
        )) {
          return true;
        }
        if (applied is! WorkspaceNoChange) {
          throw StateError('cloud_workspace_contract');
        }
      } else {
        final now = await workspace.inspectMetadata();
        if (now.revision != local.revision) {
          observed = null;
          continue;
        }
      }
      baseline = baseline.copyWith(
        favorite: keepLocalFavorite
            ? baseline.favorite ?? const CloudFavorite(false, 0)
            : favorite,
        note: noteResult.keepBaseline ? baseline.note : noteResult.note,
        assignments: assignmentBaseline,
        localOnlyTagIds: cloudWinsAssignments
            ? localOnly.intersection(tagsAtStart)
            : localOnly,
        retainLocalNote: noteResult.retain,
        observedVersion: settled ? observed.version : null,
        quotaBlocked: quotaBlocked,
      );
      await _remember(id, baseline);
      _showNote(skillId, desiredNote, noteResult.note, noteResult.retain);
      return settled;
    }
    return false;
  }

  Future<
    ({
      CloudNote note,
      bool keepLocal,
      bool keepBaseline,
      bool retain,
      bool settled,
      bool ended,
      bool accepted,
      bool quotaBlocked,
    })?
  >
  _syncNote(
    String lineageId,
    String skillId,
    String? local,
    CloudNote cloud,
    SyncMetadataBaseline prior,
  ) async {
    final previous = prior.note;
    // A server rollback can make an agreed local Note newer than the cloud.
    final versionRegressed =
        previous != null && cloud.version < previous.version;
    final dirty =
        versionRegressed ||
        prior.retainLocalNote ||
        (previous == null
            ? local != null
            : previous.value != local &&
                  previous.conflict?.contains(local) != true);
    if (cloud.conflict case final conflict?) {
      final third = local != cloud.value && !conflict.contains(local) && dirty;
      final retained = prior.retainLocalNote || third;
      return _noteResult(
        cloud,
        keepLocal: retained || conflict.contains(local),
        retain: retained,
      );
    }
    if (cloud.value == local) return _noteResult(cloud);
    final retain =
        prior.retainLocalNote || (previous?.conflict != null && dirty);
    if (retain) return _noteResult(cloud, keepLocal: true, retain: true);
    if (!dirty) return _noteResult(cloud);
    if (local != null && utf8.encode(local).length > 4096) {
      return _noteResult(cloud, keepLocal: true, keepBaseline: true);
    }
    final conflict = previous == null
        ? cloud.version > 0
        : previous.version != cloud.version;
    final now = await workspace.inspectMetadata();
    if (now.skills[skillId]?.note != local ||
        !now.skills.containsKey(skillId)) {
      return null;
    }
    final result = conflict
        ? await api.openNoteConflict(
            lineageId,
            expectedVersion: cloud.version,
            value: local,
          )
        : await api.writeNote(
            lineageId,
            expectedVersion: cloud.version,
            value: local,
          );
    switch (result) {
      case CloudApiSuccess<CloudNote>(:final value):
        if (value.conflict != null) {
          // Remember the pair before returning. A lost response or an edit
          // during the request must still settle against the current pair.
          await _remember(lineageId, prior.copyWith(note: value));
          return _noteResult(value, keepLocal: true);
        }
        return _noteResult(value, accepted: value.value == local);
      case ApiNoteConflict(:final current):
        final third =
            current.value != local && current.conflict?.contains(local) != true;
        return _noteResult(current, keepLocal: true, retain: third);
      case ApiStaleFieldVersion():
        return null;
      case ApiNotFound():
      case ApiLineageEnded():
        return _noteResult(cloud, ended: true);
      case ApiMetadataTooLarge():
        return _noteResult(cloud, keepLocal: true, keepBaseline: true);
      default:
        return _noteResult(
          cloud,
          keepLocal: true,
          keepBaseline: true,
          settled: _settled(result),
          quotaBlocked: result is ApiStorageLimitReached,
        );
    }
  }

  void _showNote(String skillId, String? local, CloudNote? note, bool retain) {
    if (note?.conflict != null || retain) {
      attention[skillId] = SyncMetadataAttention(
        MetadataAttentionReason.noteConflict,
        note: note,
        localNote: local,
        hasUnsubmittedLocalNote: retain,
      );
    } else if (local != null && utf8.encode(local).length > 4096) {
      attention[skillId] = SyncMetadataAttention(
        MetadataAttentionReason.noteTooLarge,
        note: note,
        localNote: local,
      );
    } else {
      attention.remove(skillId);
    }
  }

  Future<SyncOutcome> resolve(
    SyncLink link, {
    required int expectedVersion,
    required String? expectedLocalNote,
    required String? value,
  }) async {
    final id = link.lineageId, skillId = link.managedSkillId;
    if (id == null) return const SkillDeviceOnly();
    final baseline = (await store.metadataState()).lineages[id];
    final before = await workspace.inspectMetadata();
    final local = before.skills[skillId];
    if (local == null) return const SkillDeviceOnly();
    final displayed = attention[skillId];
    if (local.note != expectedLocalNote ||
        displayed?.note?.version != expectedVersion ||
        displayed?.reason != MetadataAttentionReason.noteConflict) {
      await syncSkill(link);
      return const WaitingToUpload();
    }
    final chosen = value?.trim();
    if (chosen == '' || (chosen != null && utf8.encode(chosen).length > 4096)) {
      // Retain the conflict and third text while the choice is corrected.
      return const WaitingToUpload();
    }
    if (chosen != local.note) {
      final applied = await workspace.applyMetadata(
        managedSkillId: skillId,
        expectedRevision: before.revision,
        favorite: local.favorite,
        note: chosen,
        tagIds: local.tagIds,
      );
      if (applied case WorkspaceApplyFailed(
        code: WorkspaceFailureCode.staleSnapshot,
      )) {
        await syncSkill(link);
        return const WaitingToUpload();
      }
      if (applied case WorkspaceApplyFailed(
        code: WorkspaceFailureCode.skillNotFound,
      )) {
        return const SkillDeviceOnly();
      }
      if (applied is! WorkspaceNoChange) {
        throw StateError('cloud_workspace_contract');
      }
    }
    final pending = (baseline ?? SyncMetadataBaseline(skillId)).copyWith(
      note: displayed!.note,
      retainLocalNote: true,
    );
    await _remember(id, pending);
    _showNote(skillId, chosen, displayed.note, true);
    final result = displayed.note!.conflict != null
        ? await api.resolveNote(
            id,
            expectedVersion: expectedVersion,
            value: chosen,
          )
        : await api.writeNote(
            id,
            expectedVersion: expectedVersion,
            value: chosen,
          );
    CloudNote? accepted;
    if (result is CloudApiSuccess<CloudNote> &&
        result.value.value == chosen &&
        result.value.conflict == null) {
      accepted = result.value;
    } else if (result is ApiUnavailable &&
        result.retryAfter == null &&
        result.code != CloudFailureCode.protocol) {
      // The choice is still on this stack. Compare current state when the
      // reply to the guarded write might have been lost.
      final read = await api.readNote(id);
      if (read is CloudApiSuccess<CloudNote> &&
          read.value.value == chosen &&
          read.value.conflict == null &&
          read.value.version >= expectedVersion) {
        accepted = read.value;
      } else if (read is ApiSignInRequired || read is ApiUnavailable) {
        return _failed(read);
      } else {
        return _failed(result);
      }
    } else if (result is ApiNotFound || result is ApiLineageEnded) {
      await forget(skillId, id);
      return const SkillDeviceOnly();
    } else if (result is ApiStaleFieldVersion ||
        result is ApiNoNoteConflict ||
        result is ApiNoteConflict ||
        result is CloudApiSuccess<CloudNote>) {
      await syncSkill(link);
      return const WaitingToUpload();
    } else if (result is ApiMetadataTooLarge) {
      return const WaitingToUpload();
    } else {
      return _failed(result);
    }
    final after = (await workspace.inspectMetadata()).skills[skillId];
    if (after == null) return const SkillDeviceOnly();
    final changed = after.note != chosen;
    await _remember(
      id,
      pending.copyWith(note: accepted, retainLocalNote: changed),
    );
    _showNote(skillId, after.note, accepted, changed);
    return changed ? const WaitingToUpload() : const SkillSynced();
  }
}

({
  CloudNote note,
  bool keepLocal,
  bool keepBaseline,
  bool retain,
  bool settled,
  bool ended,
  bool accepted,
  bool quotaBlocked,
})
_noteResult(
  CloudNote note, {
  bool keepLocal = false,
  bool keepBaseline = false,
  bool retain = false,
  bool settled = true,
  bool ended = false,
  bool accepted = false,
  bool quotaBlocked = false,
}) => (
  note: note,
  keepLocal: keepLocal,
  keepBaseline: keepBaseline,
  retain: retain,
  settled: settled,
  ended: ended,
  accepted: accepted,
  quotaBlocked: quotaBlocked,
);

CloudTag _tagValues(
  CloudTag tag, {
  required String name,
  required String? color,
}) => CloudTag(
  id: tag.id,
  name: name,
  normalizedName: tag.normalizedName,
  color: color,
  version: tag.version,
  nameVersion: tag.nameVersion,
  colorVersion: tag.colorVersion,
);

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

Set<String> _renameCycle(
  Map<String, CloudTag> pending,
  Map<String, String> localOwners,
) {
  final checked = <String>{};
  for (final root in pending.keys) {
    final path = <String>{};
    String? tag = root;
    while (tag != null && pending.containsKey(tag) && !checked.contains(tag)) {
      if (!path.add(tag)) {
        return path.skipWhile((id) => id != tag).toSet();
      }
      tag = localOwners[pending[tag]!.normalizedName];
    }
    checked.addAll(path);
  }
  return const {};
}
