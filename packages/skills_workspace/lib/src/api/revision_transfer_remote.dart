import 'revision_transfer.dart';
import '../domain/identifiers.dart';

/// One operation's remote and credential provider. Never journaled or logged.
final class RevisionTransferRemote {
  const RevisionTransferRemote({
    required this.url,
    required this.ephemeralHeaders,
  }) : allowLoopbackHttpForTesting = false;
  const RevisionTransferRemote.loopbackForTesting({
    required this.url,
    required this.ephemeralHeaders,
  }) : allowLoopbackHttpForTesting = true;
  final String url;
  final Future<List<String>> Function() ephemeralHeaders;
  final bool allowLoopbackHttpForTesting;
}

final class PushCommittedRevisionRequest {
  const PushCommittedRevisionRequest({
    required this.managedSkillId,
    required this.expectedIdentity,
    required this.expectedRevision,
    required this.batch,
    required this.remote,
  });
  final ManagedSkillId managedSkillId;
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final CommittedRevisionBatch batch;
  final RevisionTransferRemote remote;
}

final class FetchIncomingRevisionRequest {
  FetchIncomingRevisionRequest({
    this.managedSkillId,
    this.localOperationId,
    this.replaceExistingLineage = false,
    required this.expectedIdentity,
    required this.expectedRevision,
    required List<int> contentManifest,
    required this.remote,
  }) : contentManifest = List.unmodifiable(contentManifest);
  final ManagedSkillId? managedSkillId;
  final OperationId? localOperationId;
  final bool replaceExistingLineage;
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final List<int> contentManifest;
  final RevisionTransferRemote remote;
}

enum RevisionTransferRefStatus { unreported, accepted, rejected }

final class RevisionTransferReport {
  RevisionTransferReport({required List<RevisionTransferRefStatus> refs})
    : refs = List.unmodifiable(refs);
  final List<RevisionTransferRefStatus> refs;
}
