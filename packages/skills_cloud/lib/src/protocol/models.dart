import '../errors.dart';
import '../http/transport.dart';
import 'codec.dart';
import 'content_manifest.dart';

/// A complete lineage snapshot, retaining structured source provenance.
final class CloudLineage {
  /// Parses the full immutable lineage projection.
  CloudLineage.fromJson(Map<String, Object?> json)
    : lineageId = identifier(json['lineageId']),
      generation = integer(json['generation'], minimum: 1),
      selectedCommitId = text(json['selectedCommitId'], maximum: 64),
      slotKey = text(json['slotKey']),
      sourceDescriptor = CloudSourceDescriptor.fromJson(
        object(json['sourceDescriptor']),
      ),
      metadata = freezeMap(object(json['metadata'])),
      contentStatus = json['contentStatus'] == 'ready'
          ? CloudContentStatus.ready
          : CloudContentStatus.needsReupload,
      contentManifest = json['contentManifest'] == null
          ? null
          : CloudContentManifest.fromJson(object(json['contentManifest'])) {
    if (json.containsKey('contentManifestVersion') &&
        json['contentManifestVersion'] != 1) {
      throw const CloudException(CloudErrorCode.protocolVersionUnsupported);
    }
    if (contentStatus == CloudContentStatus.ready &&
        (contentManifest == null ||
            contentManifest!.currentEffective != selectedCommitId ||
            contentManifest!.slotKey != slotKey)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }

  /// The Cloud lineage identity.
  final String lineageId;

  /// The source generation.
  final int generation;

  /// The immutable selected Git revision.
  final String selectedCommitId;

  /// The source-independent Skill slot key.
  final String slotKey;

  /// The original structured source descriptor.
  final CloudSourceDescriptor sourceDescriptor;

  /// Full snapshot values, distinct from metadata change patches.
  final Map<String, Object?> metadata;
  final CloudContentStatus contentStatus;
  final CloudContentManifest? contentManifest;
  @override
  String toString() => 'CloudLineage([redacted provenance and metadata])';
}

/// A global personal-tag vocabulary item, including unassigned tags.
final class CloudPersonalTag {
  /// Parses a full snapshot tag projection.
  CloudPersonalTag.fromJson(Map<String, Object?> json)
    : tagId = identifier(json['tagId']),
      name = text(json['name']),
      color = json['color'] == null ? null : text(json['color'], maximum: 7),
      createdAt = timestamp(json['createdAt']),
      updatedAt = timestamp(json['updatedAt']);

  /// The server-minted vocabulary identity.
  final String tagId;

  /// The display name.
  final String name;

  /// The color, if configured.
  final String? color;

  /// The creation time.
  final DateTime createdAt;

  /// The last update time.
  final DateTime updatedAt;
  @override
  String toString() => 'CloudPersonalTag([redacted])';
}

/// A typed account event that distinguishes global tags from lineage events.
sealed class CloudChange {
  CloudChange._(this.sequence, Map<String, Object?> payload)
    : payload = freezeMap(payload);

  /// Parses a version-one event without inventing a lineage for global tags.
  factory CloudChange.fromJson(Map<String, Object?> json) {
    final sequence = CloudSequence.parse(json['sequence']),
        payload = object(json['payload']);
    if (json['kind'] == 'personalTag') {
      if (json['lineageId'] != null ||
          json['generation'] != null ||
          !['tagCreate', 'tagPatch', 'tagDelete'].contains(payload['kind'])) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      identifier(payload['tagId']);
      return CloudPersonalTagChange._(sequence, payload);
    }
    if (![
      'revision',
      'metadata',
      'removal',
      'replacement',
      'repairNeeded',
      'repairReady',
    ].contains(json['kind'])) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    final lineage = identifier(json['lineageId']),
        generation = integer(json['generation'], minimum: 1);
    if (payload['lineageId'] != lineage ||
        payload['generation'] != generation) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return CloudLineageChange._(
      sequence,
      payload,
      lineage,
      generation,
      json['kind']! as String,
    );
  }

  /// The exact account event sequence.
  final CloudSequence sequence;

  /// The immutable event payload, preserving omitted/null/false/empty fields.
  final Map<String, Object?> payload;

  /// The event's lineage, absent only for global vocabulary changes.
  String? get lineageId;

  /// The lineage generation, absent only for global vocabulary changes.
  int? get generation;

  /// The service event category.
  String get kind;
  @override
  String toString() =>
      'CloudChange($kind, sequence: $sequence, [redacted payload])';
}

/// A revision, metadata patch or removal bound to one lineage generation.
final class CloudLineageChange extends CloudChange {
  CloudLineageChange._(
    super.sequence,
    super.payload,
    this.lineageId,
    this.generation,
    this.kind,
  ) : super._();
  @override
  final String lineageId;
  @override
  final int generation;
  @override
  final String kind;
}

/// A personal-tag vocabulary event with genuinely absent lineage identity.
final class CloudPersonalTagChange extends CloudChange {
  CloudPersonalTagChange._(super.sequence, super.payload) : super._();
  @override
  String? get lineageId => null;
  @override
  int? get generation => null;
  @override
  String get kind => 'personalTag';
}

List<CloudChange> _changes(Object? value) {
  if (value is! List<Object?>) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return List.unmodifiable(
    value.map((item) => CloudChange.fromJson(object(item))),
  );
}

/// Structured remote source provenance, independent of Cloud repository layout.
sealed class CloudSourceDescriptor {
  /// Creates a source descriptor.
  const CloudSourceDescriptor();

  /// Parses supported remote provenance without accepting device-local paths.
  factory CloudSourceDescriptor.fromJson(Map<String, Object?> json) {
    if (json['payloadSchemaVersion'] != 1) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    final payload = object(json['payload']);
    return switch (json['kind']) {
      'git' => CloudGitSource(
        locator: text(payload['locator']),
        ref: payload['ref'] == null ? null : text(payload['ref']),
        repositorySubpath: _relative(payload['repositorySubpath']),
        skillPath: _relative(payload['skillPath']),
      ),
      'wellKnown' => CloudWellKnownSource(
        locator: text(payload['locator']),
        skillPath: _relative(payload['skillPath']),
      ),
      _ => throw const CloudException(CloudErrorCode.invalidResponse),
    };
  }

  /// The complete versioned wire projection.
  Map<String, Object?> toJson();
  @override
  String toString() => 'CloudSourceDescriptor([redacted provenance])';
}

String _relative(Object? value) {
  if (value is! String ||
      value.length > 4096 ||
      value.contains(RegExp(r'[\\\x00-\x1f]')) ||
      (value.isNotEmpty &&
          value
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..'))) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

String _remote(String locator, {required bool git}) {
  if (locator.isEmpty ||
      locator.length > 4096 ||
      locator.contains(RegExp(r'[\x00-\x20\\?#]'))) {
    throw const CloudException(CloudErrorCode.invalidRequest);
  }
  final scp = RegExp(r'^([^@/\s]+)@[^@:/\s]+:.+$').firstMatch(locator);
  if (git && scp != null) {
    if (Uri.decodeComponent(scp[1]!).contains(':')) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return locator;
  }
  final uri = Uri.tryParse(locator);
  if (uri == null ||
      uri.host.isEmpty ||
      ![if (git) 'ssh', 'https'].contains(uri.scheme) ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme == 'https' && uri.userInfo.isNotEmpty) ||
      (uri.userInfo.isNotEmpty &&
          Uri.decodeComponent(uri.userInfo).contains(':')) ||
      (git && !uri.pathSegments.any((part) => part.isNotEmpty))) {
    throw const CloudException(CloudErrorCode.invalidRequest);
  }
  return locator;
}

/// Git provenance retaining ref, repository subpath and Skill path.
final class CloudGitSource extends CloudSourceDescriptor {
  /// Creates credential-free remote Git provenance.
  CloudGitSource({
    required String locator,
    required this.ref,
    required String repositorySubpath,
    required String skillPath,
  }) : locator = _remote(locator, git: true),
       repositorySubpath = _relative(repositorySubpath),
       skillPath = _relative(skillPath);

  /// The original remote source locator, never a Cloud upload credential.
  final String locator;

  /// The source ref, if specified.
  final String? ref;

  /// The repository-relative source root.
  final String repositorySubpath;

  /// The source-relative Skill path.
  final String skillPath;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'git',
    'payloadSchemaVersion': 1,
    'payload': {
      'locator': locator,
      'ref': ref,
      'repositorySubpath': repositorySubpath,
      'skillPath': skillPath,
    },
  };
}

/// Well-known HTTPS provenance retaining the original Skill path.
final class CloudWellKnownSource extends CloudSourceDescriptor {
  /// Creates a credential-free HTTPS source.
  CloudWellKnownSource({required String locator, required String skillPath})
    : locator = _remote(locator, git: false),
      skillPath = _relative(skillPath);

  /// The original well-known endpoint.
  final String locator;

  /// The source-relative Skill path.
  final String skillPath;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'wellKnown',
    'payloadSchemaVersion': 1,
    'payload': {'locator': locator, 'skillPath': skillPath},
  };
}

/// A successful or replayed business commit receipt.
final class CloudCommitReceipt {
  /// Parses a receipt without converting its sequence to a JSON number.
  CloudCommitReceipt.fromJson(Map<String, Object?> json)
    : operationId = identifier(json['operationId']),
      lineageId = identifier(json['lineageId']),
      generation = integer(json['generation'], minimum: 1),
      commitId = text(json['commitId'], maximum: 64),
      sequence = CloudSequence.parse(json['sequence']),
      outcome = text(json['outcome'], maximum: 16),
      expiresAt = timestamp(json['receiptExpiresAt']),
      contentManifest = CloudContentManifest.fromJson(
        object(json['contentManifest']),
      ) {
    if (!['committed', 'replay'].contains(outcome) ||
        json['contentManifestVersion'] != 1 ||
        contentManifest.currentEffective != commitId) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }

  /// The full retained upstream/effective/history manifest from the receipt.
  final CloudContentManifest contentManifest;

  /// The immutable business intent identity.
  final String operationId;

  /// The server lineage identity.
  final String lineageId;

  /// The source generation.
  final int generation;

  /// The selected Git commit.
  final String commitId;

  /// The account change sequence.
  final CloudSequence sequence;

  /// The committed or replay outcome.
  final String outcome;

  /// The guaranteed receipt retention boundary.
  final DateTime expiresAt;
  @override
  String toString() =>
      'CloudCommitReceipt(sequence: $sequence, [redacted identifiers])';
}

/// One bounded account change page whose cursor is never advanced implicitly.
final class CloudChangesPage {
  /// Parses decimal cursors and immutable event payloads.
  CloudChangesPage.fromJson(Map<String, Object?> json)
    : after = CloudSequence.parse(json['after']),
      highWatermark = CloudSequence.parse(json['highWatermark']),
      nextCursor = CloudSequence.parse(json['nextCursor']),
      entries = _changes(json['entries']) {
    if (after.compareTo(nextCursor) > 0 ||
        nextCursor.compareTo(highWatermark) > 0) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    var previous = after;
    for (final entry in entries) {
      if (entry.sequence.compareTo(previous) <= 0 ||
          entry.sequence.compareTo(highWatermark) > 0) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      previous = entry.sequence;
    }
    if (nextCursor != previous) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }

  /// The requested lower boundary.
  final CloudSequence after;

  /// The fixed page-set upper boundary.
  final CloudSequence highWatermark;

  /// The received cursor; persistence belongs to the caller's inbox transaction.
  final CloudSequence nextCursor;

  /// The immutable versioned event payloads.
  final List<CloudChange> entries;
  @override
  String toString() =>
      'CloudChangesPage([redacted entries], cursor: $nextCursor)';
}

/// A page from one materialized snapshot with a fixed high-water mark.
final class CloudSnapshotPage {
  /// Parses a page while preserving source, metadata and global tag payloads.
  CloudSnapshotPage.fromJson(Map<String, Object?> json)
    : snapshotId = identifier(json['snapshotId']),
      highWatermark = CloudSequence.parse(json['highWatermark']),
      pageCursor = json['pageCursor'] == null ? null : text(json['pageCursor']),
      nextPageCursor = json['nextPageCursor'] == null
          ? null
          : text(json['nextPageCursor']),
      complete = boolean(json['complete']),
      items = List.unmodifiable(
        _objects(json['items']).map(CloudLineage.fromJson),
      ),
      personalTags = List.unmodifiable(
        _objects(json['personalTags']).map(CloudPersonalTag.fromJson),
      ) {
    if (complete != (nextPageCursor == null)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }

  /// The server snapshot identity.
  final String snapshotId;

  /// The immutable snapshot boundary.
  final CloudSequence highWatermark;

  /// The current opaque page cursor.
  final String? pageCursor;

  /// The next opaque cursor, if incomplete.
  final String? nextPageCursor;

  /// Whether every item and personal tag has been received.
  final bool complete;

  /// Full lineage projections, including structured source descriptors.
  final List<CloudLineage> items;

  /// Global personal tags, including unassigned tags.
  final List<CloudPersonalTag> personalTags;
  @override
  String toString() =>
      'CloudSnapshotPage(complete: $complete, [redacted contents])';
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?>) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return List.unmodifiable(value.map((item) => freezeMap(object(item))));
}
