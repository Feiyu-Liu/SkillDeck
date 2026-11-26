export '../domain/activation_selection.dart';

import '../domain/activation_selection.dart';
import '../domain/identifiers.dart';
import '../domain/lock_wait_policy.dart';
import '../domain/public_models.dart';
import '../domain/personal_tag_color.dart';
import '../domain/source_descriptor.dart';
import 'destructive_intent.dart';

final class InspectAgentsRequest {
  const InspectAgentsRequest();
}

final class InspectSourceRequest {
  const InspectSourceRequest({
    required this.source,
    this.includeInternal = false,
    this.fullDepth = false,
  });

  final SourceDescriptor source;
  final bool includeInternal;
  final bool fullDepth;
}

/// Requests an immutable manifest for the currently selected Effective
/// Revision. Markdown filtering and decoding remain an application concern.
final class ListEffectiveFilesRequest {
  const ListEffectiveFilesRequest({required this.managedSkillId});

  final ManagedSkillId managedSkillId;
}

/// Requests exactly one file from the current Effective Revision.
///
/// [expectedContentHash] is a read precondition: it prevents callers from
/// pairing a previously listed manifest with bytes from a later revision.
/// Input validation is deliberately deferred to the operation so malformed
/// caller input resolves as a typed [SkillsFailure] rather than throwing from
/// a public request constructor.
final class ReadEffectiveFileRequest {
  const ReadEffectiveFileRequest({
    required this.managedSkillId,
    required this.expectedContentHash,
    required this.relativePath,
  });

  final ManagedSkillId managedSkillId;
  final String expectedContentHash;
  final String relativePath;
}

final class InstallRequest {
  InstallRequest({
    required this.source,
    Set<String>? selectedSkillNames,
    this.includeInternal = false,
    this.fullDepth = false,
    this.activationSelection = const ActivationSelection.automatic(),
    this.activationMode = RequestedActivationMode.automatic,
    this.lockWaitPolicy,
  }) : selectedSkillNames = selectedSkillNames == null
           ? null
           : Set.unmodifiable(selectedSkillNames) {
    _requireOptionalStringSet(this.selectedSkillNames, 'selectedSkillNames');
  }

  final SourceDescriptor source;
  final Set<String>? selectedSkillNames;
  final bool includeInternal;
  final bool fullDepth;
  final ActivationSelection activationSelection;
  final RequestedActivationMode activationMode;
  final LockWaitPolicy? lockWaitPolicy;
}

final class ConfirmInstallTakeoverRequest {
  const ConfirmInstallTakeoverRequest({
    required this.draft,
    this.lockWaitPolicy,
  });

  final InstallTakeoverDraft draft;
  final LockWaitPolicy? lockWaitPolicy;
}

final class AdoptRequest {
  const AdoptRequest({
    required this.selection,
    this.activationMode = RequestedActivationMode.automatic,
    this.lockWaitPolicy,
  });

  final ExternalAdoptionSelection selection;
  final RequestedActivationMode activationMode;
  final LockWaitPolicy? lockWaitPolicy;
}

final class CheckUpdatesRequest {
  CheckUpdatesRequest({Set<ManagedSkillId>? managedSkillIds})
    : managedSkillIds = managedSkillIds == null
          ? null
          : Set.unmodifiable(managedSkillIds) {
    _requireOptionalIdSet(this.managedSkillIds, 'managedSkillIds');
  }

  final Set<ManagedSkillId>? managedSkillIds;
}

final class UpdateRequest {
  UpdateRequest({
    required Set<ManagedSkillId> managedSkillIds,
    this.lockWaitPolicy,
  }) : managedSkillIds = Set.unmodifiable(managedSkillIds) {
    _requireIdSet(this.managedSkillIds, 'managedSkillIds');
  }

  final Set<ManagedSkillId> managedSkillIds;
  final LockWaitPolicy? lockWaitPolicy;
}

final class ReplaceSourceRequest {
  const ReplaceSourceRequest({
    required this.managedSkillId,
    required this.source,
    required this.intent,
    this.includeInternal = false,
    this.fullDepth = false,
    this.lockWaitPolicy,
  });

  final ManagedSkillId managedSkillId;
  final SourceDescriptor source;
  final DestructiveIntent intent;
  final bool includeInternal;
  final bool fullDepth;
  final LockWaitPolicy? lockWaitPolicy;
}

final class InspectActivationTargetsRequest {
  InspectActivationTargetsRequest({required this.scope, this.projectRootId}) {
    if (scope == ActivationScope.project && projectRootId == null) {
      throw ArgumentError('Project inspection requires projectRootId.');
    }
    if (scope == ActivationScope.global && projectRootId != null) {
      throw ArgumentError('Global inspection cannot include projectRootId.');
    }
  }

  final ActivationScope scope;
  final String? projectRootId;
}

final class ActivateRequest {
  ActivateRequest({
    required Set<ManagedSkillId> managedSkillIds,
    required this.selection,
    this.mode = RequestedActivationMode.automatic,
    this.lockWaitPolicy,
  }) : managedSkillIds = Set.unmodifiable(managedSkillIds) {
    _requireIdSet(this.managedSkillIds, 'managedSkillIds');
    if (selection is NoActivationSelection) {
      throw ArgumentError('activate requires an Activation target.');
    }
  }

  final Set<ManagedSkillId> managedSkillIds;
  final ActivationSelection selection;
  final RequestedActivationMode mode;
  final LockWaitPolicy? lockWaitPolicy;
}

final class ConfirmActivationTakeoverRequest {
  const ConfirmActivationTakeoverRequest({
    required this.draft,
    this.lockWaitPolicy,
  });

  final ActivationTakeoverDraft draft;
  final LockWaitPolicy? lockWaitPolicy;
}

final class DeactivateRequest {
  DeactivateRequest({
    required Set<ManagedSkillId> managedSkillIds,
    Set<String>? locations,
    this.lockWaitPolicy,
  }) : managedSkillIds = Set.unmodifiable(managedSkillIds),
       locations = locations == null ? null : Set.unmodifiable(locations) {
    _requireIdSet(this.managedSkillIds, 'managedSkillIds');
    _requireOptionalStringSet(this.locations, 'locations');
  }

  final Set<ManagedSkillId> managedSkillIds;
  final Set<String>? locations;
  final LockWaitPolicy? lockWaitPolicy;
}

final class DiscoverExternalSkillsRequest {
  const DiscoverExternalSkillsRequest({
    this.selection = const ActivationSelection.automatic(),
    this.includeInternal = false,
    this.scanAllKnownLocations = false,
  });

  final ActivationSelection selection;
  final bool includeInternal;
  final bool scanAllKnownLocations;
}

final class RegisterProjectRootRequest {
  RegisterProjectRootRequest({required this.path, this.id}) {
    _requireNonEmpty(path, 'path');
    if (id != null) _requireNonEmpty(id!, 'id');
  }

  final String path;
  final String? id;
}

final class UnregisterProjectRootRequest {
  UnregisterProjectRootRequest({required this.id}) {
    _requireNonEmpty(id, 'id');
  }

  final String id;
}

final class RemoveRequest {
  RemoveRequest({
    required Set<ManagedSkillId> managedSkillIds,
    required this.intent,
    this.lockWaitPolicy,
  }) : managedSkillIds = Set.unmodifiable(managedSkillIds) {
    _requireIdSet(this.managedSkillIds, 'managedSkillIds');
  }

  final Set<ManagedSkillId> managedSkillIds;
  final DestructiveIntent intent;
  final LockWaitPolicy? lockWaitPolicy;
}

final class ReconfigureAgentCatalogRequest {
  ReconfigureAgentCatalogRequest({required List<AgentDefinition> agents})
    : agents = List.unmodifiable(agents) {
    final ids = agents.map((agent) => agent.id).toSet();
    if (ids.length != agents.length) {
      throw ArgumentError.value(agents, 'agents', 'contains duplicate IDs');
    }
  }

  final List<AgentDefinition> agents;
}

final class InspectAgentRootOwnershipRequest {
  const InspectAgentRootOwnershipRequest();
}

final class SetFavoriteRequest {
  const SetFavoriteRequest({
    required this.managedSkillId,
    required this.isFavorite,
  });

  final ManagedSkillId managedSkillId;
  final bool isFavorite;
}

final class SaveNoteRequest {
  SaveNoteRequest({required this.managedSkillId, required this.text}) {
    _requireNonEmpty(text, 'text');
  }

  final ManagedSkillId managedSkillId;
  final String text;
}

final class DeleteNoteRequest {
  const DeleteNoteRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class CreatePersonalTagRequest {
  CreatePersonalTagRequest({required this.name, this.color}) {
    _requireNonEmpty(name, 'name');
  }

  final String name;
  final String? color;
}

final class UpdatePersonalTagRequest {
  UpdatePersonalTagRequest({
    required this.tagId,
    required this.name,
    this.color,
  }) {
    _requireNonEmpty(tagId, 'tagId');
    _requireNonEmpty(name, 'name');
  }

  final String tagId;
  final String name;
  final String? color;
}

final class DeletePersonalTagRequest {
  DeletePersonalTagRequest({required this.tagId}) {
    _requireNonEmpty(tagId, 'tagId');
  }

  final String tagId;
}

final class AssignPersonalTagRequest {
  AssignPersonalTagRequest({
    required this.managedSkillId,
    required this.tagId,
  }) {
    _requireNonEmpty(tagId, 'tagId');
  }

  final ManagedSkillId managedSkillId;
  final String tagId;
}

final class UnassignPersonalTagRequest {
  UnassignPersonalTagRequest({
    required this.managedSkillId,
    required this.tagId,
  }) {
    _requireNonEmpty(tagId, 'tagId');
  }

  final ManagedSkillId managedSkillId;
  final String tagId;
}

final class EnsureDraftRequest {
  const EnsureDraftRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class InspectDraftRequest {
  const InspectDraftRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class DiscardDraftRequest {
  const DiscardDraftRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class PublishDraftRequest {
  const PublishDraftRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class InspectUpdateCandidateRequest {
  const InspectUpdateCandidateRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class ResolveUpdateConflictRequest {
  ResolveUpdateConflictRequest({
    required this.managedSkillId,
    required this.path,
    required this.resolutionState,
  }) {
    _requireNonEmpty(path, 'path');
    if (path.startsWith('/') ||
        path.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path) ||
        path.contains('\u0000') ||
        path.split(RegExp(r'[/\\]+')).any((segment) => segment == '..')) {
      throw ArgumentError.value(path, 'path', 'must be a safe relative path');
    }
  }

  final ManagedSkillId managedSkillId;
  final String path;
  final UpdateConflictResolutionState resolutionState;
}

final class PublishUpdateCandidateRequest {
  const PublishUpdateCandidateRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class AbandonUpdateCandidateRequest {
  const AbandonUpdateCandidateRequest({required this.managedSkillId});
  final ManagedSkillId managedSkillId;
}

final class OperationHistoryRequest {
  const OperationHistoryRequest({
    this.managedSkillId,
    this.cursor,
    this.limit = 50,
  }) : assert(limit > 0);

  final ManagedSkillId? managedSkillId;
  final String? cursor;
  final int limit;
}

/// Reads the Workspace changes committed after a caller's cursor.
final class InspectCommittedChangesRequest {
  const InspectCommittedChangesRequest({required this.since});

  final RepositoryRevision since;
}

/// Reads the current published revision selections for the requested Skills.
final class InspectRevisionSelectionsRequest {
  InspectRevisionSelectionsRequest({
    required Set<ManagedSkillId> managedSkillIds,
  }) : managedSkillIds = Set.unmodifiable(managedSkillIds);

  final Set<ManagedSkillId> managedSkillIds;
}

final class PublishedHistoryRequest {
  const PublishedHistoryRequest({
    required this.managedSkillId,
    this.cursor,
    this.limit = 50,
  }) : assert(limit > 0);

  final ManagedSkillId managedSkillId;
  final String? cursor;
  final int limit;
}

final class InspectDiffRequest {
  const InspectDiffRequest({
    required this.managedSkillId,
    this.from,
    required this.to,
  });

  final ManagedSkillId managedSkillId;
  final OperationSubjectReference? from;
  final OperationSubjectReference to;
}

final class RestorePublishRequest {
  const RestorePublishRequest({
    required this.managedSkillId,
    required this.selectedRevision,
  });

  final ManagedSkillId managedSkillId;
  final OperationSubjectReference selectedRevision;
}

final class InspectSkillDriftRequest {
  const InspectSkillDriftRequest({required this.managedSkillId});

  final ManagedSkillId managedSkillId;
}

final class ExportSkillDriftArtifactRequest {
  const ExportSkillDriftArtifactRequest({
    required this.review,
    required this.artifactId,
    required this.destinationDirectory,
  });

  final SkillDriftReview review;
  final String artifactId;
  final String destinationDirectory;
}

/// Exports the current published heads of a Skill to a new pack file.
final class ExportRevisionPackRequest {
  const ExportRevisionPackRequest({
    required this.managedSkillId,
    required this.destinationPath,
  });

  final ManagedSkillId managedSkillId;
  final String destinationPath;
}

/// Details for applying a remote selection.
sealed class ApplyRemoteStateRequest {
  const ApplyRemoteStateRequest();
}

final class RemoteSkillContent extends ApplyRemoteStateRequest {
  const RemoteSkillContent({
    required this.managedSkillId,
    required this.expectedEffective,
    required this.effective,
    this.upstream,
    this.packPath,
  });

  final ManagedSkillId managedSkillId;
  final RevisionId expectedEffective;
  final RevisionId effective;
  final RevisionId? upstream;
  final String? packPath;
}

/// Replaces the Skill's library metadata with the supplied final values.
final class RemoteSkillMetadata extends ApplyRemoteStateRequest {
  RemoteSkillMetadata({
    required this.managedSkillId,
    required this.expectedEffective,
    required this.favorite,
    required String? note,
    required Iterable<String> tagIds,
  }) : note = note?.trim(),
       tagIds = Set.unmodifiable(tagIds) {
    if (this.note?.isEmpty == true) {
      throw ArgumentError('A non-null note must contain text.');
    }
  }

  final ManagedSkillId managedSkillId;
  final RevisionId expectedEffective;
  final bool favorite;
  final String? note;
  final Set<String> tagIds;
}

final class RemoteSkillRemoval extends ApplyRemoteStateRequest {
  const RemoteSkillRemoval({
    required this.managedSkillId,
    required this.expectedEffective,
  });

  final ManagedSkillId managedSkillId;
  final RevisionId expectedEffective;
}

sealed class RemoteTagVocabulary extends ApplyRemoteStateRequest {
  const RemoteTagVocabulary._();

  factory RemoteTagVocabulary.ensure({
    required String name,
    required String? color,
  }) = RemoteTagEnsure;
  factory RemoteTagVocabulary.update({
    required String tagId,
    required String name,
    required String? color,
  }) = RemoteTagUpdate;
  factory RemoteTagVocabulary.delete({required String tagId}) = RemoteTagDelete;
}

final class RemoteTagEnsure extends RemoteTagVocabulary {
  RemoteTagEnsure({required this.name, required this.color}) : super._() {
    _requireNonEmpty(name, 'name');
    validateColor(color);
  }

  final String name;
  final String? color;
}

final class RemoteTagUpdate extends RemoteTagVocabulary {
  RemoteTagUpdate({
    required this.tagId,
    required this.name,
    required this.color,
  }) : super._() {
    _requireNonEmpty(tagId, 'tagId');
    _requireNonEmpty(name, 'name');
    validateColor(color);
  }

  final String tagId;
  final String name;
  final String? color;
}

final class RemoteTagDelete extends RemoteTagVocabulary {
  RemoteTagDelete({required this.tagId}) : super._() {
    _requireNonEmpty(tagId, 'tagId');
  }

  final String tagId;
}

/// Installs a portable source directly from a downloaded Revision Pack.
final class RemoteSkillInstall extends ApplyRemoteStateRequest {
  RemoteSkillInstall({
    required this.packPath,
    required this.effective,
    this.upstream,
    required this.source,
  }) {
    final expectsUpstream = switch (source) {
      GitSourceDescriptor() || WellKnownSourceDescriptor() => true,
      SyncedOriginSourceDescriptor(:final originSourceType) =>
        originSourceType != SyncedOriginSourceType.adoptedSnapshot,
      LocalSourceDescriptor() || AdoptedSnapshotSourceDescriptor() =>
        throw ArgumentError('Remote install requires a portable source.'),
    };
    if (expectsUpstream != (upstream != null)) {
      throw ArgumentError('Upstream does not match the remote source type.');
    }
  }

  final String packPath;
  final RevisionId effective;
  final RevisionId? upstream;
  final SourceDescriptor source;
}

/// Stages the requested revisions from a caller-supplied pack file.
final class ImportRevisionPackRequest {
  ImportRevisionPackRequest({
    required this.managedSkillId,
    required this.packPath,
    required Iterable<RevisionId> revisions,
  }) : revisions = Set<RevisionId>.unmodifiable(revisions) {
    if (this.revisions.isEmpty) {
      throw ArgumentError(
        'A Revision Pack import requires at least one revision.',
      );
    }
  }

  final ManagedSkillId managedSkillId;
  final String packPath;
  final Set<RevisionId> revisions;
}

final class ResolveSkillDriftRequest {
  const ResolveSkillDriftRequest({
    required this.review,
    required this.resolution,
  });

  final SkillDriftReview review;
  final SkillDriftResolution resolution;
}

final class ValidateWorkspaceRequest {
  const ValidateWorkspaceRequest({this.managedSkillIds});

  final Set<ManagedSkillId>? managedSkillIds;
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireIdSet(Set<ManagedSkillId> values, String name) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
}

void _requireOptionalIdSet(Set<ManagedSkillId>? values, String name) {
  if (values != null && values.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
}

void _requireOptionalStringSet(Set<String>? values, String name) {
  if (values != null &&
      (values.isEmpty || values.any((value) => value.trim().isEmpty))) {
    throw ArgumentError.value(values, name, 'must contain non-empty values');
  }
}
