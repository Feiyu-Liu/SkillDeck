import 'package:path/path.dart' as p;
import 'package:skills_cloud/skills_cloud.dart' as cloud;
import 'package:skills_manager/features/cloud/data/cloud_device_identity.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/workspace_sync.dart';

/// A failed read is distinct from an absent Skill or an empty change set.
final class WorkspaceSyncReadFailure implements Exception {
  const WorkspaceSyncReadFailure(this.code);

  final cloud.WorkspaceFailureCode code;

  @override
  String toString() => 'Workspace sync read failed: ${code.name}';
}

final class WorkspaceSyncAdapter implements cloud.SyncWorkspace {
  const WorkspaceSyncAdapter({
    required SkillsWorkspaceRepository repository,
    required String deviceLabel,
    required CloudDeviceIdentity deviceIdentity,
    void Function(String skillId, bool applying)? onApplying,
  }) : _repository = repository,
       _deviceLabel = deviceLabel,
       _deviceIdentity = deviceIdentity,
       _onApplying = onApplying;

  final SkillsWorkspaceRepository _repository;
  final String _deviceLabel;
  final CloudDeviceIdentity _deviceIdentity;
  final void Function(String skillId, bool applying)? _onApplying;

  @override
  String? slotKeyForName(String declaredName) =>
      _repository.deriveSlotKey(declaredName);

  @override
  Future<List<cloud.WorkspaceSkill>> listSkills() => _inspect(null);

  @override
  Future<cloud.WorkspaceSkill?> inspectRevisionSelections(
    String managedSkillId,
  ) async => (await _inspect(WorkspaceSkillId(managedSkillId))).firstOrNull;

  Future<List<cloud.WorkspaceSkill>> _inspect(WorkspaceSkillId? skillId) async {
    var snapshot = _repository.current ?? await _refresh();
    // Heads and provenance must describe the same Workspace commit.
    for (var attempt = 0; attempt < 2; attempt++) {
      final ids = skillId == null
          ? {for (final item in snapshot.skills) item.id}
          : {skillId};
      final selection = _read(
        await _repository.inspectRevisionSelections(ids).completed,
      );
      if (selection.revision == snapshot.revision) {
        return [
          for (final entry in selection.heads.entries)
            if (snapshot.findSkillById(entry.key) case final skill?)
              _skill(skill, entry.value),
        ];
      }
      snapshot = _repository.current ?? snapshot;
      if (snapshot.revision != selection.revision) snapshot = await _refresh();
    }
    throw const WorkspaceSyncReadFailure(
      cloud.WorkspaceFailureCode.staleSnapshot,
    );
  }

  Future<SkillsWorkspaceSnapshot> _refresh() async =>
      _read(await _repository.refresh());

  @override
  Future<cloud.WorkspaceChanges> inspectCommittedChanges(String? cursor) async {
    final since = cursor == null ? 0 : int.tryParse(cursor);
    if (since == null || since < 0) {
      throw const WorkspaceSyncReadFailure(
        cloud.WorkspaceFailureCode.staleSnapshot,
      );
    }
    final changes = _read(
      await _repository.inspectCommittedChanges(since).completed,
    );
    if (changes.resetRequired) {
      final restored = _read(
        await _repository.inspectCommittedChanges(0).completed,
      );
      final snapshot = await _refresh();
      return cloud.WorkspaceChanges(
        skillIds: {
          for (final id in restored.skillIds) id.value,
          for (final skill in snapshot.skills) skill.id.value,
        },
        cursor: restored.revision.toString(),
      );
    }
    return cloud.WorkspaceChanges(
      skillIds: changes.skillIds.map((id) => id.value),
      cursor: changes.revision.toString(),
    );
  }

  @override
  Future<cloud.WorkspaceExport> exportRevisionPack(
    String managedSkillId,
    String destination,
  ) async => switch (await _repository
      .exportRevisionPack(WorkspaceSkillId(managedSkillId), destination)
      .completed) {
    WorkspaceCompleted(:final value) => cloud.WorkspaceExported(
      effective: value.effective,
      upstream: value.upstream,
    ),
    WorkspaceFailed(:final failure) => cloud.WorkspaceExportFailed(
      _failureCode(failure),
    ),
    WorkspaceCommittedPending() => const cloud.WorkspaceExportFailed(
      cloud.WorkspaceFailureCode.operationFailed,
    ),
  };

  @override
  Future<cloud.WorkspaceApply> applyContent({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
    required String effective,
    required String? upstream,
    required String packPath,
  }) => _apply(
    () => WorkspaceRemoteContent(
      skillId: WorkspaceSkillId(managedSkillId),
      expectedEffective: expectedEffective,
      expectedSourceEpoch: expectedSourceEpoch,
      heads: (effective: effective, upstream: upstream),
      packPath: packPath,
    ),
    managedSkillId: managedSkillId,
  );

  @override
  Future<cloud.WorkspaceApply> install({
    required String packPath,
    required String effective,
    required String? upstream,
    required cloud.PortableSource source,
  }) => _apply(
    () => WorkspaceRemoteInstall(
      heads: (effective: effective, upstream: upstream),
      packPath: packPath,
      source: _localSource(source),
    ),
  );

  @override
  Future<cloud.WorkspaceApply> remove({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
  }) => _apply(
    () => WorkspaceRemoteRemoval(
      WorkspaceSkillId(managedSkillId),
      expectedEffective,
      expectedSourceEpoch: expectedSourceEpoch,
    ),
    managedSkillId: managedSkillId,
  );

  @override
  Future<cloud.WorkspaceApply> replaceSource({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
    required String packPath,
    required String effective,
    required String? upstream,
    required cloud.PortableSource source,
  }) => _apply(
    () => WorkspaceRemoteSourceReplacement(
      skillId: WorkspaceSkillId(managedSkillId),
      expectedEffective: expectedEffective,
      expectedSourceEpoch: expectedSourceEpoch,
      heads: (effective: effective, upstream: upstream),
      packPath: packPath,
      source: _localSource(source),
    ),
    managedSkillId: managedSkillId,
  );

  Future<cloud.WorkspaceApply> _apply(
    WorkspaceRemoteChange Function() request, {
    String? managedSkillId,
  }) async {
    final WorkspaceRemoteChange change;
    try {
      change = request();
    } on ArgumentError {
      return const cloud.WorkspaceApplyFailed(
        cloud.WorkspaceFailureCode.invalidSkill,
      );
    }
    if (managedSkillId != null) _onApplying?.call(managedSkillId, true);
    try {
      final completion = await _repository.applyRemoteState(change).completed;
      return switch (completion) {
        WorkspaceCompleted(:final value) => switch (value.kind) {
          WorkspaceRemoteResultKind.noChange => cloud.WorkspaceNoChange(
            sourceEpoch: value.sourceEpoch,
          ),
          WorkspaceRemoteResultKind.fastForwarded =>
            const cloud.WorkspaceFastForwarded(),
          WorkspaceRemoteResultKind.merged => cloud.WorkspaceMerged(
            value.effective!,
          ),
          WorkspaceRemoteResultKind.conflicted =>
            const cloud.WorkspaceConflicted(),
          WorkspaceRemoteResultKind.draftResolutionRequired =>
            const cloud.WorkspaceDraftRequired(),
          WorkspaceRemoteResultKind.slotOccupied => cloud.WorkspaceSlotOccupied(
            value.skillId!.value,
          ),
          WorkspaceRemoteResultKind.installed => cloud.WorkspaceInstalled(
            value.skillId!.value,
            sourceEpoch: value.sourceEpoch,
          ),
          WorkspaceRemoteResultKind.removed => const cloud.WorkspaceRemoved(),
          WorkspaceRemoteResultKind.sourceReplaced =>
            cloud.WorkspaceSourceReplaced(sourceEpoch: value.sourceEpoch),
          WorkspaceRemoteResultKind.unsupported =>
            const cloud.WorkspaceApplyFailed(
              cloud.WorkspaceFailureCode.operationFailed,
            ),
        },
        WorkspaceFailed(:final failure) => cloud.WorkspaceApplyFailed(
          _failureCode(failure),
        ),
        WorkspaceCommittedPending() => const cloud.WorkspaceApplyFailed(
          cloud.WorkspaceFailureCode.operationFailed,
        ),
      };
    } finally {
      if (managedSkillId != null) _onApplying?.call(managedSkillId, false);
    }
  }

  cloud.WorkspaceSkill _skill(
    WorkspaceSkill skill,
    WorkspaceSelectedRevisions heads,
  ) {
    try {
      return cloud.WorkspaceSkill(
        id: skill.id.value,
        effective: heads.effective,
        upstream: heads.upstream,
        source: _portableSource(skill),
        declaredName: skill.declaredName,
        slotKey: skill.slotKey,
        sourceEpoch: heads.sourceEpoch,
      );
    } on ArgumentError {
      throw const WorkspaceSyncReadFailure(
        cloud.WorkspaceFailureCode.invalidSkill,
      );
    }
  }

  cloud.PortableSource _portableSource(WorkspaceSkill skill) {
    final source = skill.source;
    return switch (source.kind) {
      WorkspaceSourceKind.git when !_localGit(source.locator) =>
        cloud.PortableSource.git(
          locator: source.locator,
          ref: source.ref,
          repositorySubpath: source.repositorySubpath,
          skillPath: source.skillPath,
        ),
      WorkspaceSourceKind.wellKnown => cloud.PortableSource.wellKnown(
        locator: source.locator,
        skillPath: source.skillPath,
      ),
      WorkspaceSourceKind.git ||
      WorkspaceSourceKind.local ||
      WorkspaceSourceKind.adoptedSnapshot => cloud.PortableSource.deviceBound(
        originSourceType: source.kind == WorkspaceSourceKind.adoptedSnapshot
            ? 'adoptedSnapshot'
            : 'local',
        originDeviceLabel: _deviceLabel,
        displayLabel: _deviceBoundDisplayLabel(
          source.locator,
          skill.declaredName,
        ),
        originSourceId: _deviceIdentity.sourceIdFor([
          source.kind.name,
          source.locator,
          source.ref,
          source.repositorySubpath,
          source.skillPath,
          source.adoptedContentHash,
        ]),
      ),
      WorkspaceSourceKind.syncedOrigin when source.syncedOrigin != null =>
        cloud.PortableSource.deviceBound(
          originSourceType: source.syncedOrigin!.originKind.name,
          originDeviceLabel: source.syncedOrigin!.deviceLabel,
          displayLabel: source.syncedOrigin!.displayLabel,
          originSourceId: source.syncedOrigin!.sourceId,
        ),
      WorkspaceSourceKind.syncedOrigin => throw ArgumentError(
        'Missing synced origin provenance',
      ),
    };
  }
}

bool _localGit(String locator) =>
    p.posix.isAbsolute(locator) ||
    p.windows.isAbsolute(locator) ||
    Uri.tryParse(locator)?.scheme == 'file';

String _deviceBoundDisplayLabel(String locator, String fallback) {
  final name = Uri.tryParse(locator)?.scheme == 'file'
      ? Uri.parse(locator).pathSegments.lastOrNull ?? ''
      : p.windows.isAbsolute(locator) && !p.posix.isAbsolute(locator)
      ? p.windows.basename(locator)
      : p.posix.basename(locator);
  return name.trim().isEmpty ||
          name.runes.length > 256 ||
          RegExp(r'[/\\:\x00-\x1f\x7f-\x9f]').hasMatch(name)
      ? fallback
      : name;
}

SkillSourceProvenance _localSource(cloud.PortableSource source) {
  final value = source.toJson();
  return switch (value['type']) {
    'git' => SkillSourceProvenance(
      kind: WorkspaceSourceKind.git,
      locator: value['locator'] as String,
      ref: value['ref'] as String?,
      repositorySubpath: value['repositorySubpath'] as String,
      skillPath: value['skillPath'] as String,
    ),
    'wellKnown' => SkillSourceProvenance(
      kind: WorkspaceSourceKind.wellKnown,
      locator: value['locator'] as String,
      skillPath: value['skillPath'] as String,
    ),
    'deviceBound' => SkillSourceProvenance(
      kind: WorkspaceSourceKind.syncedOrigin,
      locator: '',
      syncedOrigin: (
        originKind: source.isAdoptedSnapshot
            ? WorkspaceSourceKind.adoptedSnapshot
            : WorkspaceSourceKind.local,
        deviceLabel: value['originDeviceLabel'] as String,
        displayLabel: value['displayLabel'] as String,
        sourceId: value['originSourceId'] as String?,
      ),
    ),
    _ => throw ArgumentError('Unsupported portable source type'),
  };
}

T _read<T>(WorkspaceCompletion<T> completion) => switch (completion) {
  WorkspaceCompleted(:final value) => value,
  WorkspaceFailed(:final failure) => throw WorkspaceSyncReadFailure(
    _failureCode(failure),
  ),
  WorkspaceCommittedPending() => throw const WorkspaceSyncReadFailure(
    cloud.WorkspaceFailureCode.operationFailed,
  ),
};

cloud.WorkspaceFailureCode _failureCode(WorkspaceFailure failure) => switch ((
  failure.code,
  failure.context['reason'],
)) {
  (WorkspaceErrorCode.skillNotFound, _) =>
    cloud.WorkspaceFailureCode.skillNotFound,
  (WorkspaceErrorCode.staleSnapshot, _) =>
    cloud.WorkspaceFailureCode.staleSnapshot,
  (WorkspaceErrorCode.archiveInvalid, _) ||
  (
    _,
    'packMalformed' || 'packIncomplete',
  ) => cloud.WorkspaceFailureCode.invalidPack,
  (WorkspaceErrorCode.revisionStoreCorrupt, _) =>
    cloud.WorkspaceFailureCode.objectUnavailable,
  (
    WorkspaceErrorCode.invalidSkill || WorkspaceErrorCode.unsupportedSkillName,
    _,
  ) =>
    cloud.WorkspaceFailureCode.invalidSkill,
  (WorkspaceErrorCode.ioFailure, 'destinationUnavailable') =>
    cloud.WorkspaceFailureCode.destinationUnusable,
  (WorkspaceErrorCode.operationCancelled, _) =>
    cloud.WorkspaceFailureCode.cancelled,
  (WorkspaceErrorCode.ioFailure, _) => cloud.WorkspaceFailureCode.ioFailure,
  _ => cloud.WorkspaceFailureCode.operationFailed,
};
