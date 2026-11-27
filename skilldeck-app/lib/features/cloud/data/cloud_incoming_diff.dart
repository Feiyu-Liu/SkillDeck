import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/workspace_review.dart';

/// Read and compare one verified Head Pack without applying it to Workspace.
Future<Object?> readCloudIncomingDiff({
  required Reconciler reconciler,
  required SkillsWorkspaceRepository workspace,
  required WorkspaceSkillId skillId,
}) async {
  final local = await reconciler.workspace.inspectRevisionSelections(
    skillId.value,
  );
  final link = (await reconciler.state.links())
      .where((link) => link.managedSkillId == skillId.value)
      .firstOrNull;
  final lineageId = link?.lineageId;
  if (local == null || lineageId == null) return null;
  final read = await reconciler.api.readLineage(lineageId);
  if (read is ApiSignInRequired) {
    return const SyncAccountCondition(ApiSignInRequired());
  }
  if (read is! CloudApiSuccess<Lineage>) return null;
  final lineage = read.value, head = lineage.head;
  if (head == null || lineage.state != LineageState.live) return null;
  final temp = await Directory.systemTemp.createTemp('skilldeck-cloud-review-');
  try {
    final pack = p.join(temp.path, 'incoming.pack');
    final downloaded = await reconciler.api.downloadPack(
      lineageId,
      generation: lineage.generation,
      digest: head.pack,
      path: pack,
    );
    if (downloaded is ApiSignInRequired) {
      return const SyncAccountCondition(ApiSignInRequired());
    }
    if (downloaded is! CloudApiSuccess<String>) return null;
    return switch (await workspace
        .inspectRevisionPackDiff(
          skillId: skillId,
          expectedEffective: local.effective,
          incomingEffective: head.effective,
          incomingUpstream: head.upstream,
          packPath: pack,
        )
        .completed) {
      WorkspaceCompleted<WorkspaceRevisionPackDiff>(:final value) => value,
      _ => null,
    };
  } finally {
    await temp.delete(recursive: true);
  }
}
