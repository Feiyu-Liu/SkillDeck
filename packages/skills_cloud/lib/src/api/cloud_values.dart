import 'metadata_values.dart';

/// Opaque SHA-256 identifier of a Revision Pack.
final class PackDigest {
  PackDigest(this.value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError('Invalid pack digest');
    }
  }
  final String value;
  @override
  bool operator ==(Object other) => other is PackDigest && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// A published cloud head. Revision strings are opaque to the client.
final class LineageHead {
  LineageHead({
    required this.effective,
    required this.upstream,
    required this.pack,
    required this.declaredName,
    this.deviceName,
    this.devicePlatform,
  }) {
    revision(effective);
    if (upstream != null) revision(upstream!);
  }
  final String effective;
  final String? upstream;
  final PackDigest pack;
  final String declaredName;
  final String? deviceName;
  final String? devicePlatform;
  Map<String, Object?> get selection => {
    'effective': effective,
    'upstream': upstream,
  };
  Map<String, Object?> get next => {
    ...selection,
    'pack': pack.value,
    'declaredName': declaredName,
  };
  Map<String, Object?> toJson() => {
    ...next,
    'device': {'name': deviceName, 'platform': devicePlatform},
  };
  factory LineageHead.fromJson(Object? value) {
    final m = jsonObject(value), device = jsonObject(m['device']);
    return LineageHead(
      effective: jsonString(m['effective']),
      upstream: nullableString(m['upstream']),
      pack: PackDigest(jsonString(m['pack'])),
      declaredName: jsonString(m['declaredName']),
      deviceName: nullableString(device['name']),
      devicePlatform: nullableString(device['platform']),
    );
  }
}

enum LineageState { live, removed, stopped }

final class Lineage {
  Lineage({
    required this.id,
    required this.version,
    required this.state,
    required this.generation,
    required Map<String, Object?> source,
    required this.head,
    required this.updatedAt,
  }) : source = Map.unmodifiable(source);
  final String id;
  final int version;
  final LineageState state;
  final int generation;
  final Map<String, Object?> source;
  final LineageHead? head;
  final DateTime updatedAt;
  factory Lineage.fromJson(Object? value) {
    final m = jsonObject(value);
    final id = jsonString(m['lineageId']);
    if (id.isEmpty || id.length > 64) {
      throw const FormatException('cloud_protocol');
    }
    final result = Lineage(
      id: id,
      version: positive(m['version']),
      state: LineageState.values.byName(jsonString(m['state'])),
      generation: positive(m['generation']),
      source: jsonObject(m['source']),
      head: m['head'] == null ? null : LineageHead.fromJson(m['head']),
      updatedAt: DateTime.parse(jsonString(m['updatedAt'])),
    );
    if (result.state != LineageState.live && result.head != null) {
      throw const FormatException('cloud_protocol');
    }
    return result;
  }
  Map<String, Object?> toJson() => {
    'lineageId': id,
    'version': version,
    'state': state.name,
    'generation': generation,
    'source': source,
    'head': head?.toJson(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

final class LibraryPage {
  LibraryPage({
    required Iterable<Lineage> lineages,
    required this.next,
    required this.feedCursor,
    Iterable<LineageMetadata>? metadata,
    this.tagVocabulary,
  }) : lineages = List.unmodifiable(lineages),
       metadata = metadata == null ? null : List.unmodifiable(metadata);
  final List<Lineage> lineages;
  final String? next;
  final String feedCursor;
  final List<LineageMetadata>? metadata;
  final TagVocabulary? tagVocabulary;
  factory LibraryPage.fromJson(Object? value, {bool includeMetadata = false}) {
    final m = jsonObject(value);
    final lineages = jsonList(m['lineages']).map(Lineage.fromJson).toList();
    final metadata = includeMetadata
        ? jsonList(m['metadata']).map(LineageMetadata.fromJson).toList()
        : null;
    if (metadata != null &&
        (metadata.length != lineages.length ||
            Iterable<int>.generate(lineages.length)
                .any((i) => lineages[i].id != metadata[i].lineageId) ||
            !m.containsKey('tagVocabulary'))) {
      throw const FormatException('cloud_protocol');
    }
    return LibraryPage(
      lineages: lineages,
      next: nullableString(m['next']),
      feedCursor: jsonString(m['feedCursor']),
      metadata: metadata,
      tagVocabulary: !includeMetadata || m['tagVocabulary'] == null
          ? null
          : TagVocabulary.fromJson(m['tagVocabulary']),
    );
  }
}

final class FeedEntry {
  const FeedEntry({
    required this.kind,
    required this.id,
    required this.version,
  });
  final String kind;
  final String id;
  final int version;
  bool get isLineage => kind == 'lineage';
  bool get isMetadata => kind == 'metadata';
  bool get isTagVocabulary => kind == 'tagVocabulary';
  factory FeedEntry.fromJson(Object? value) {
    final m = jsonObject(value);
    return FeedEntry(
      kind: jsonString(m['kind']),
      id: jsonString(m['id']),
      version: positive(m['version']),
    );
  }
}

final class FeedPage {
  FeedPage({
    required Iterable<FeedEntry> entries,
    required this.cursor,
    required this.more,
  }) : entries = List.unmodifiable(entries);
  final List<FeedEntry> entries;
  final String cursor;
  final bool more;
  factory FeedPage.fromJson(Object? value) {
    final m = jsonObject(value);
    if (m['more'] is! bool) throw const FormatException('cloud_protocol');
    return FeedPage(
      entries: jsonList(m['entries']).map(FeedEntry.fromJson),
      cursor: jsonString(m['cursor']),
      more: m['more'] as bool,
    );
  }
}

final class PackUploaded {
  const PackUploaded(this.digest, this.commits);
  final PackDigest digest;
  final int commits;
}

// Internal decoding helpers are hidden by the public export.
Map<String, Object?> jsonObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('cloud_protocol');
  }
  return value;
}

List<Object?> jsonList(Object? value) {
  if (value is! List<Object?>) throw const FormatException('cloud_protocol');
  return value;
}

String jsonString(Object? value) {
  if (value is! String) throw const FormatException('cloud_protocol');
  return value;
}

String? nullableString(Object? value) =>
    value == null ? null : jsonString(value);
int positive(Object? value) {
  if (value is! int || value < 1) throw const FormatException('cloud_protocol');
  return value;
}

void revision(String value) {
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    throw const FormatException('cloud_protocol');
  }
}
