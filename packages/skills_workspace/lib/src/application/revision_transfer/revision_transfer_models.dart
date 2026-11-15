import 'dart:typed_data';

import '../../domain/revision_transfer.dart';
import '../../domain/public_models.dart';
import '../../domain/identifiers.dart';
import '../../domain/revision_content.dart';
import '../../domain/draft_snapshot.dart';
import '../operations/operation_models.dart';
import '../runtime/revision_engine_port.dart';
import '../update/update_models.dart';

final class IncomingRevisionContent {
  IncomingRevisionContent({
    required this.upstream,
    required this.effective,
    required List<RevisionObjectId> roots,
    required this.packBytes,
    required this.indexBytes,
    required this.contentHash,
    required this.history,
  }) : roots = List.unmodifiable(roots);
  final RevisionObjectId upstream;
  final RevisionObjectId effective;
  final List<RevisionObjectId> roots;
  final Uint8List packBytes;
  final Uint8List indexBytes;
  final String contentHash;
  final List<
    ({RevisionObjectId objectId, CommittedRevisionHistoryDescriptor descriptor})
  >
  history;
}

final class IncomingRevisionPreflight {
  const IncomingRevisionPreflight({
    required this.skill,
    required this.state,
    required this.content,
    required this.localPublishedRoots,
  });
  final ManagedSkill skill;
  final UpdateRevisionState state;
  final IncomingRevisionContent content;
  final List<RevisionObjectId> localPublishedRoots;
}

final class PreparedIncomingRevision {
  const PreparedIncomingRevision({
    required this.preflight,
    required this.upstreamTree,
    required this.upstreamDeclaredName,
    required this.effectiveTree,
    required this.declaredName,
    required this.description,
    required this.draftFingerprint,
    required this.historyTrees,
  });
  final IncomingRevisionPreflight preflight;
  final NormalizedSkillTree upstreamTree;
  final String upstreamDeclaredName;
  final NormalizedSkillTree effectiveTree;
  final String declaredName;
  final String description;
  final DraftFingerprint? draftFingerprint;
  final Map<RevisionObjectId, NormalizedSkillTree> historyTrees;
  SourceLineageReference get lineage => preflight.state.sourceLineage;
}

final class PreparedIncomingInstallation {
  const PreparedIncomingInstallation({
    required this.managedSkillId,
    required this.lineage,
    required this.batch,
    required this.content,
    required this.upstreamTree,
    required this.effectiveTree,
    required this.historyTrees,
    required this.declaredName,
    required this.upstreamDeclaredName,
    required this.description,
  });
  final ManagedSkillId managedSkillId;
  final SourceLineageReference lineage;
  final CommittedRevisionBatch batch;
  final IncomingRevisionContent content;
  final NormalizedSkillTree upstreamTree, effectiveTree;
  final Map<RevisionObjectId, NormalizedSkillTree> historyTrees;
  final String declaredName, upstreamDeclaredName, description;
}

final class IncomingRevisionRejected implements Exception {
  const IncomingRevisionRejected(this.reason);
  final IncomingRevisionPendingReason reason;
}
