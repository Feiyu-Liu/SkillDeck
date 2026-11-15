import '../../domain/revision_content.dart';
import '../../domain/cancellation.dart';

/// Health information returned by the private Revision Engine boundary.
final class RevisionEngineStatus {
  const RevisionEngineStatus({required this.protocolVersion});

  final int protocolVersion;

  @override
  bool operator ==(Object other) =>
      other is RevisionEngineStatus && other.protocolVersion == protocolVersion;

  @override
  int get hashCode => protocolVersion.hashCode;
}

/// Internal object address inside one isolated Revision Store.
final class RevisionObjectId {
  RevisionObjectId(String value) : value = _validate(value);

  final String value;

  static String _validate(String value) {
    if (value.length != 40 || !RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'must be a lowercase SHA-1 object ID',
      );
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is RevisionObjectId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One derived retention reference inside an isolated Revision Store.
///
/// References are never business authority and are not exposed through the
/// public repository API.  The fixed namespace prevents callers from
/// mutating a branch, tag, remote, or symbolic HEAD through this seam.
final class RevisionRetentionRef {
  RevisionRetentionRef({required this.name, required this.target}) {
    if (!name.startsWith('refs/skills-workspace/')) {
      throw ArgumentError.value(name, 'name', 'outside retention namespace');
    }
    if (name.length <= 'refs/skills-workspace/'.length ||
        name.contains('..') ||
        name.contains('\\') ||
        name.contains('\u0000') ||
        !RegExp(r'^[0-9A-Za-z._/-]+$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'invalid retention reference');
    }
  }

  final String name;
  final RevisionObjectId target;

  @override
  bool operator ==(Object other) =>
      other is RevisionRetentionRef &&
      other.name == name &&
      other.target == target;

  @override
  int get hashCode => Object.hash(name, target);
}

/// Stable machine meaning attached to an internal commit.
///
/// Product history is indexed by SQLite Operation Records. These values only
/// keep the Git graph inspectable without turning commit messages into a
/// second business-event protocol.
enum RevisionCommitKind {
  initial,
  upstream,
  effectiveUpdate,
  localPublish,
  restorePublish,
  updateCandidate,
}

/// Immutable commit topology requested from the Revision Engine.
final class RevisionCommitRequest {
  RevisionCommitRequest({
    required this.tree,
    required List<RevisionObjectId> parents,
    required this.kind,
  }) : parents = List<RevisionObjectId>.unmodifiable(parents) {
    if (parents.length > 2) {
      throw ArgumentError.value(parents, 'parents', 'supports at most 2');
    }
    final expectedParentCount = switch (kind) {
      RevisionCommitKind.initial => 0,
      RevisionCommitKind.upstream ||
      RevisionCommitKind.localPublish ||
      RevisionCommitKind.restorePublish ||
      RevisionCommitKind.updateCandidate => 1,
      RevisionCommitKind.effectiveUpdate => 2,
    };
    if (parents.length != expectedParentCount) {
      throw ArgumentError.value(
        parents,
        'parents',
        '${kind.name} requires $expectedParentCount parent(s)',
      );
    }
  }

  final RevisionObjectId tree;
  final List<RevisionObjectId> parents;
  final RevisionCommitKind kind;
}

/// Bounded immutable commit topology without author or message text.
final class RevisionCommitTopology {
  RevisionCommitTopology({
    required this.tree,
    required List<RevisionObjectId> parents,
  }) : parents = List.unmodifiable(parents);

  final RevisionObjectId tree;
  final List<RevisionObjectId> parents;
}

/// Caller-selected bounds for a new topology inspection.
final class RevisionCommitInspectionLimits {
  const RevisionCommitInspectionLimits({
    this.maximumCommitBytes = 64 * 1024,
    this.maximumParentCount = 64,
  });
  final int maximumCommitBytes;
  final int maximumParentCount;
}

/// Resource bounds for local object graph validation, independent of quotas.
final class RevisionObjectImportLimits {
  const RevisionObjectImportLimits({
    this.maximumObjectCount = 100000,
    this.maximumObjectBytes = 32 * 1024 * 1024,
    this.maximumTotalBytes = 256 * 1024 * 1024,
    this.maximumCommitBytes = 64 * 1024,
    this.maximumParentCount = 64,
    this.maximumDeltaDepth = 64,
  });

  final int maximumObjectCount;
  final int maximumObjectBytes;
  final int maximumTotalBytes;
  final int maximumCommitBytes;
  final int maximumParentCount;
  final int maximumDeltaDepth;
}

/// Counts the exact verified root closure, including already-present objects.
final class RevisionObjectImportReport {
  const RevisionObjectImportReport({
    required this.objectCount,
    required this.totalBytes,
  });

  final int objectCount;
  final int totalBytes;
}

enum RevisionChangeKind { added, deleted, modified, renamed, typeChanged }

/// One normalized path change between two immutable commits.
final class RevisionChange {
  const RevisionChange({
    required this.kind,
    required this.oldPath,
    required this.newPath,
    required this.oldExecutable,
    required this.newExecutable,
    required this.binary,
  });

  final RevisionChangeKind kind;
  final String? oldPath;
  final String? newPath;
  final bool oldExecutable;
  final bool newExecutable;
  final bool binary;
}

/// One typed three-way merge conflict.
final class RevisionMergeConflict {
  const RevisionMergeConflict({
    required this.ancestorPath,
    required this.currentPath,
    required this.incomingPath,
  });

  final String? ancestorPath;
  final String? currentPath;
  final String? incomingPath;
}

sealed class RevisionMergeResult {
  const RevisionMergeResult();
}

final class RevisionMergeClean extends RevisionMergeResult {
  const RevisionMergeClean(this.tree);

  final RevisionObjectId tree;
}

final class RevisionMergeConflicted extends RevisionMergeResult {
  RevisionMergeConflicted({
    required this.tree,
    required List<RevisionMergeConflict> conflicts,
  }) : conflicts = List<RevisionMergeConflict>.unmodifiable(conflicts) {
    if (conflicts.isEmpty) {
      throw ArgumentError.value(conflicts, 'conflicts', 'must not be empty');
    }
  }

  final RevisionObjectId tree;
  final List<RevisionMergeConflict> conflicts;
}

enum RevisionEngineFailureCode {
  invalidInput,
  storeUnavailable,
  objectUnavailable,
  verificationFailed,
  bundleInvalid,
  unexpectedFailure,
  cancelled,
  limitExceeded,
}

/// Stable private failure crossing the Revision worker boundary.
///
/// Native diagnostics and paths deliberately remain inside the worker.
final class RevisionEngineException implements Exception {
  const RevisionEngineException(this.code);

  final RevisionEngineFailureCode code;

  @override
  String toString() => 'RevisionEngineException(${code.name})';
}

/// Private application port for the long-lived Revision Engine worker.
///
/// Git handles, refs, native diagnostics and the worker wire protocol remain
/// behind this boundary. SQLite owns revision selection; this port only owns
/// immutable content, graph mechanics and pack/index recovery artifacts.
abstract interface class RevisionEnginePort {
  Future<RevisionEngineStatus> status();

  Future<void> createStore(String repositoryPath);

  Future<void> verifyStore(String repositoryPath);

  Future<RevisionObjectId> writeTree(
    String repositoryPath,
    NormalizedSkillTree tree,
  );

  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commitOrTree,
  );

  Future<RevisionObjectId> createCommit(
    String repositoryPath,
    RevisionCommitRequest request,
  );

  Future<void> verifyCommit(
    String repositoryPath,
    RevisionObjectId commit,
    RevisionCommitRequest expected,
  );

  /// Reads the tree and every ordered parent without exposing commit metadata.
  /// Defaults to 64 KiB metadata and 64 parents; callers can choose larger
  /// bounds. Exceeding a selected budget is `limitExceeded`, never corruption.
  Future<RevisionCommitTopology> inspectCommit(
    String repositoryPath,
    RevisionObjectId commit, {
    RevisionCommitInspectionLimits limits =
        const RevisionCommitInspectionLimits(),
  });

  /// Copies a complete, bounded root closure from immutable private staging.
  ///
  /// Validates source hashes/types/connectivity before the first target write;
  /// missing source objects cannot be satisfied by objects in the target.
  /// Imports no unrelated, Draft, configuration or ref state. Pack inputs first
  /// use [restoreRecoveryPack] to create a private staged repository.
  ///
  /// No selection/ref changes occur. Cancellation or an I/O failure during
  /// copying can leave unreferenced immutable objects; it is never a business
  /// commit or an assertion that bytes were rolled back. Journal/pinning and
  /// any subsequent selection remain the caller's transactional responsibility.
  Future<RevisionObjectImportReport> importObjects({
    required String repositoryPath,
    required String stagedRepositoryPath,
    required List<RevisionObjectId> retainedRoots,
    RevisionObjectImportLimits limits = const RevisionObjectImportLimits(),
    CancellationToken? cancellationToken,
  });

  Future<bool> isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  });

  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  });

  Future<RevisionMergeResult> merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  });

  /// Writes `objects.pack` and `objects.idx` into an existing empty staging
  /// directory. Durability and atomic Bundle publication belong to the
  /// operation filesystem adapter.
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
    RevisionObjectImportLimits? limits,
  });

  /// Creates a bounded index for an untrusted raw pack in an empty owned dir.
  /// Streaming size validation precedes libgit2; no external thin-pack bases.
  Future<void> createPackIndex({
    required String packPath,
    required String stagingDirectory,
    RevisionObjectImportLimits limits = const RevisionObjectImportLimits(),
    CancellationToken? cancellationToken,
  });

  /// Reconstructs a new bare Store from a verified Bundle pack/index pair.
  ///
  /// The destination must not be the live Store. The caller verifies and
  /// durably swaps the staged Store through the operation filesystem adapter.
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
    RevisionObjectImportLimits? limits,
    CancellationToken? cancellationToken,
  });

  /// Replaces only the package-owned derived retention refs in one Store.
  ///
  /// The engine must remove stale refs in its fixed namespace and converge to
  /// exactly [references].  SQLite and Journal state remain the authority;
  /// this operation is a repairable derived-state write.
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) async {
    // Lightweight test adapters may not model derived refs. The production
    // Native Assets adapter overrides this seam; callers that require refs
    // must surface this unsupported result rather than treating refs as
    // business authority.
    throw UnsupportedError('Retention refs are unavailable.');
  }

  Future<void> close();
}
