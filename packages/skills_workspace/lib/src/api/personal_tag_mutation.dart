import '../domain/identifiers.dart';
import 'revision_transfer.dart';

enum PersonalTagMutationKind { create, update, delete }

final class PersonalTagMutation {
  PersonalTagMutation({
    required this.kind,
    this.personalTagId,
    this.name,
    this.color,
  }) {
    if (kind == PersonalTagMutationKind.create && personalTagId != null ||
        kind != PersonalTagMutationKind.create &&
            (personalTagId == null || personalTagId!.isEmpty) ||
        kind != PersonalTagMutationKind.delete &&
            (name == null || name!.trim().isEmpty || name!.length > 1024) ||
        color != null &&
            (color!.length != 7 ||
                !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color!))) {
      throw ArgumentError('Invalid Personal Tag mutation.');
    }
  }
  final PersonalTagMutationKind kind;
  final String? personalTagId, name, color;
}

final class PersonalTagCommandBinding {
  const PersonalTagCommandBinding({
    required this.operationId,
    required this.requestFingerprint,
    required this.personalTagId,
    required this.expectedIdentity,
  });
  final OperationId operationId;
  final String requestFingerprint, personalTagId;
  final WorkspaceIdentity expectedIdentity;
}

final class ReservePersonalTagMutationRequest {
  const ReservePersonalTagMutationRequest({
    required this.expectedIdentity,
    required this.expectedRevision,
    required this.localOperationId,
    required this.mutation,
  });
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final OperationId localOperationId;
  final PersonalTagMutation mutation;
}

final class ApplyPersonalTagMutationRequest {
  const ApplyPersonalTagMutationRequest({
    required this.binding,
    required this.expectedRevision,
    required this.mutation,
  });
  final PersonalTagCommandBinding binding;
  final RepositoryRevision expectedRevision;
  final PersonalTagMutation mutation;
}

final class InspectPersonalTagMutationOutcomeRequest {
  const InspectPersonalTagMutationOutcomeRequest({required this.binding});
  final PersonalTagCommandBinding binding;
}

enum PersonalTagMutationStatus {
  applied,
  confirmedNotStarted,
  rolledBack,
  inProgress,
  committedFinalizationPending,
  unknown,
  conflict,
  nameConflict,
  tagNotFound,
}

final class PersonalTagMutationOutcome {
  const PersonalTagMutationOutcome({
    required this.status,
    required this.binding,
    this.capture,
    this.committedRevision,
  });
  final PersonalTagMutationStatus status;
  final PersonalTagCommandBinding binding;
  final AuthoritativeWorkspaceCapture? capture;
  final RepositoryRevision? committedRevision;
}
