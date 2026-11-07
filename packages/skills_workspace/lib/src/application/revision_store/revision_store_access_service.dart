import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/revision_content.dart';
import '../ports/revision_store_access_ports.dart';
import '../runtime/revision_engine_port.dart';
import 'managed_skill_revision_access_gate.dart';
import 'revision_store_access_models.dart';

/// Coordinates linearizable reads from one managed Skill's canonical Store.
final class RevisionStoreAccessService
    implements CurrentEffectiveRevisionContentPort {
  RevisionStoreAccessService({
    required RevisionPointerReaderPort pointers,
    required ManagedSkillRevisionAccessGate accessGate,
    required RevisionStorePathResolver storePath,
    required RevisionEnginePort revisionEngine,
    int maxPointerAttempts = 3,
  }) : _pointers = pointers,
       _accessGate = accessGate,
       _storePath = storePath,
       _revisionEngine = revisionEngine,
       _maxPointerAttempts = maxPointerAttempts {
    if (maxPointerAttempts < 1) {
      throw ArgumentError.value(
        maxPointerAttempts,
        'maxPointerAttempts',
        'must be positive',
      );
    }
  }

  final RevisionPointerReaderPort _pointers;
  final ManagedSkillRevisionAccessGate _accessGate;
  final RevisionStorePathResolver _storePath;
  final RevisionEnginePort _revisionEngine;
  final int _maxPointerAttempts;

  /// Reads the current Effective tree at the Pointer revalidation linearization
  /// point. A Source Replacement racing the first selection causes a fresh
  /// SQLite selection and gate admission instead of reading across a switch.
  @override
  Future<NormalizedSkillTree> readCurrentEffective(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    for (var attempt = 0; attempt < _maxPointerAttempts; attempt += 1) {
      _throwIfCancelled(token);
      final selected = await _pointers.readCurrentEffective(managedSkillId);
      if (selected == null) {
        throw const RevisionStoreAccessException(
          RevisionStoreAccessFailureCode.selectionUnavailable,
        );
      }
      final ManagedSkillRevisionAccessPermit permit;
      try {
        permit = await _accessGate.acquireRead(
          managedSkillId,
          cancellationToken: token,
        );
      } on ManagedSkillRevisionAccessCancelled {
        throw const RevisionStoreAccessException(
          RevisionStoreAccessFailureCode.cancelled,
        );
      }
      try {
        _throwIfCancelled(token);
        final revalidated = await _pointers.readCurrentEffective(
          managedSkillId,
        );
        if (revalidated != selected) continue;
        return await _revisionEngine.readTree(
          _storePath(managedSkillId),
          selected.objectId,
        );
      } finally {
        await permit.release();
      }
    }
    throw const RevisionStoreAccessException(
      RevisionStoreAccessFailureCode.selectionChangedRepeatedly,
    );
  }
}

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) {
    throw const RevisionStoreAccessException(
      RevisionStoreAccessFailureCode.cancelled,
    );
  }
}
