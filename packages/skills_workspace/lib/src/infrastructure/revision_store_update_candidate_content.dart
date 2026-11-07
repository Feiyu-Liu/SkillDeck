import 'dart:convert';

import '../application/ports/revision_store_access_ports.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/operations/operation_models.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/update/update_candidate_content_port.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/revision_content.dart';
import '../domain/slot_key.dart';
import 'source/frontmatter_parser.dart';
import 'source/source_models.dart';

/// Reads candidate frontmatter under shared canonical Store admission.
///
/// Candidate descriptions and names remain content authority in the Revision
/// Store instead of being duplicated into the SQLite Session row.
final class RevisionStoreUpdateCandidateContent
    implements UpdateCandidateContentPort {
  const RevisionStoreUpdateCandidateContent({
    required ManagedSkillRevisionAccessGate accessGate,
    required RevisionStorePathResolver storePath,
    required RevisionPointerReaderPort pointers,
    required RevisionEnginePort revisionEngine,
  }) : _accessGate = accessGate,
       _storePath = storePath,
       _pointers = pointers,
       _revisionEngine = revisionEngine;

  final ManagedSkillRevisionAccessGate _accessGate;
  final RevisionStorePathResolver _storePath;
  final RevisionPointerReaderPort _pointers;
  final RevisionEnginePort _revisionEngine;

  @override
  Future<UpdateCandidateContent?> readCandidateContent({
    required ManagedSkillId managedSkillId,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId candidateObjectId,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) return null;
    final ManagedSkillRevisionAccessPermit permit;
    try {
      permit = await _accessGate.acquireRead(
        managedSkillId,
        cancellationToken: cancellationToken,
      );
    } on Object {
      return null;
    }
    try {
      final selected = await _pointers.readCurrentEffective(managedSkillId);
      if (cancellationToken.isCancelled ||
          selected?.sourceLineage != sourceLineage) {
        return null;
      }
      final tree = await _revisionEngine.readTree(
        _storePath(managedSkillId),
        candidateObjectId,
      );
      if (cancellationToken.isCancelled) return null;
      final frontmatter = _frontmatter(tree);
      if (frontmatter == null) return null;
      final slot = deriveSlotKeyValue(frontmatter.declaredName).value;
      if (slot == null) return null;
      return UpdateCandidateContent(
        declaredName: frontmatter.declaredName,
        slotKey: slot,
        description: frontmatter.description,
      );
    } on Object {
      return null;
    } finally {
      await permit.release();
    }
  }
}

SkillFrontmatter? _frontmatter(NormalizedSkillTree tree) {
  for (final file in tree.files) {
    if (file.relativePath != 'SKILL.md') continue;
    try {
      return parseSkillFrontmatter(
        utf8.decode(file.bytes, allowMalformed: false),
      );
    } on FormatException {
      return null;
    }
  }
  return null;
}
