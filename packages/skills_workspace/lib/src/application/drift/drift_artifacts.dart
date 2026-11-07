import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/public_models.dart';
import '../ports/published_artifact_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';

/// Stable public identity independent of inspection/list ordering.
String driftArtifactId(SkillMaterializationArtifact artifact) =>
    artifact.locationKind == SkillDriftLocationKind.repositoryCopy
    ? 'repositoryCopy'
    : 'activation:${sha256.convert(utf8.encode(artifact.targetPath)).toString().substring(0, 16)}';

List<SkillDriftArtifact> driftArtifactsFor(
  SkillMaterializationInspection inspected,
) => List.unmodifiable([
  for (final artifact in inspected.artifacts)
    if (artifact.inspection.state == PublishedArtifactState.mismatching)
      _publicArtifact(artifact),
]);

SkillDriftArtifact _publicArtifact(SkillMaterializationArtifact artifact) {
  final observed = artifact.inspection;
  final directory = observed.observedEntryKind == ObservedEntryKind.directory;
  final file = observed.observedEntryKind == ObservedEntryKind.file;
  return SkillDriftArtifact(
    artifactId: driftArtifactId(artifact),
    locationKind: artifact.locationKind,
    driftKind: SkillDriftKind.values.byName(observed.mismatchKind!.name),
    targetPath: artifact.locationKind == SkillDriftLocationKind.repositoryCopy
        ? null
        : artifact.targetPath,
    activationLocation: artifact.activation?.location,
    scope: artifact.activation?.scope,
    projectRootId: artifact.activation?.projectRootId,
    agentIds: artifact.activation?.agentIds ?? const [],
    fileCount: directory && observed.fingerprint != null
        ? observed.fileCount
        : null,
    byteSize: (directory || file) && observed.fingerprint != null
        ? observed.byteSize
        : null,
    canKeepExternal:
        directory &&
        observed.fingerprint != null &&
        observed.mismatchKind == PublishedArtifactMismatchKind.contentChanged &&
        artifact.locationKind != SkillDriftLocationKind.symbolicLinkActivation,
    canExport:
        (directory || file) &&
        observed.fingerprint != null &&
        !observed.containsSymbolicLinks,
  );
}
