import '../api/cloud_values.dart';
import '../api/metadata_values.dart';

/// Committed observations in one origin/account/device scope. Contains no
/// credentials, paths, pending operations or old Note history.
final class SyncMetadataState {
  const SyncMetadataState({
    this.bootstrapped = false,
    this.knownTagIds,
    this.eligibleTagIds = const {},
    this.tags = const {},
    this.lineages = const {},
  });

  final bool bootstrapped;
  final Set<String>? knownTagIds;
  final Set<String> eligibleTagIds;
  final Map<String, SyncTagBaseline> tags;
  final Map<String, SyncMetadataBaseline> lineages;

  SyncMetadataState copyWith({
    bool? bootstrapped,
    Set<String>? knownTagIds,
    Set<String>? eligibleTagIds,
    Map<String, SyncTagBaseline>? tags,
    Map<String, SyncMetadataBaseline>? lineages,
  }) => SyncMetadataState(
    bootstrapped: bootstrapped ?? this.bootstrapped,
    knownTagIds: knownTagIds == null
        ? this.knownTagIds
        : Set.unmodifiable(knownTagIds),
    eligibleTagIds: eligibleTagIds == null
        ? this.eligibleTagIds
        : Set.unmodifiable(eligibleTagIds),
    tags: tags == null ? this.tags : Map.unmodifiable(tags),
    lineages: lineages == null ? this.lineages : Map.unmodifiable(lineages),
  );

  factory SyncMetadataState.fromJson(
    Map<String, Object?> json,
  ) => SyncMetadataState(
    bootstrapped: jsonBool(json['bootstrapped']),
    knownTagIds: json['knownTagIds'] == null ? null : _ids(json['knownTagIds']),
    eligibleTagIds: _ids(json['eligibleTagIds']),
    tags: Map.unmodifiable(
      jsonObject(json['tags']).map((key, value) {
        final tag = SyncTagBaseline.fromJson(value);
        if (tag.remote.id != key) throw const FormatException('cloud_protocol');
        return MapEntry(key, tag);
      }),
    ),
    lineages: Map.unmodifiable(
      jsonObject(json['lineages']).map(
        (key, value) =>
            MapEntry(metadataId(key), SyncMetadataBaseline.fromJson(value)),
      ),
    ),
  );

  Map<String, Object?> toJson() => {
    'bootstrapped': bootstrapped,
    'knownTagIds': knownTagIds?.toList(),
    'eligibleTagIds': eligibleTagIds.toList(),
    'tags': tags.map((key, value) => MapEntry(key, value.toJson())),
    'lineages': lineages.map((key, value) => MapEntry(key, value.toJson())),
  };
}

final class SyncTagBaseline {
  const SyncTagBaseline(this.localId, this.remote);
  final String localId;
  final CloudTag remote;

  factory SyncTagBaseline.fromJson(Object? value) {
    final json = jsonObject(value);
    return SyncTagBaseline(
      jsonString(json['localId']),
      CloudTag.fromJson(json['remote']),
    );
  }

  Map<String, Object?> toJson() => {
    'localId': localId,
    'remote': remote.toJson(),
  };
}

final class SyncMetadataBaseline {
  const SyncMetadataBaseline(
    this.localId, {
    this.favorite,
    this.note,
    this.assignments,
    this.localOnlyTagIds = const {},
    this.retainLocalNote = false,
    this.observedVersion,
    this.quotaBlocked = false,
  });
  final String localId;
  final CloudFavorite? favorite;
  final CloudNote? note;
  final Map<String, CloudAssignment>? assignments;
  final Set<String> localOnlyTagIds;
  final bool retainLocalNote;
  final int? observedVersion;
  final bool quotaBlocked;

  SyncMetadataBaseline copyWith({
    CloudFavorite? favorite,
    CloudNote? note,
    Map<String, CloudAssignment>? assignments,
    Set<String>? localOnlyTagIds,
    bool? retainLocalNote,
    int? observedVersion,
    bool? quotaBlocked,
  }) => SyncMetadataBaseline(
    localId,
    favorite: favorite ?? this.favorite,
    note: note ?? this.note,
    assignments: assignments == null
        ? this.assignments
        : Map.unmodifiable(assignments),
    localOnlyTagIds: localOnlyTagIds == null
        ? this.localOnlyTagIds
        : Set.unmodifiable(localOnlyTagIds),
    retainLocalNote: retainLocalNote ?? this.retainLocalNote,
    observedVersion: observedVersion ?? this.observedVersion,
    quotaBlocked: quotaBlocked ?? this.quotaBlocked,
  );

  factory SyncMetadataBaseline.fromJson(Object? value) {
    final json = jsonObject(value);
    return SyncMetadataBaseline(
      jsonString(json['localId']),
      favorite: json['favorite'] == null
          ? null
          : CloudFavorite.fromJson(json['favorite']),
      note: json['note'] == null ? null : CloudNote.fromJson(json['note']),
      assignments: json['assignments'] == null
          ? null
          : Map.unmodifiable(
              jsonObject(json['assignments']).map((key, value) {
                final assignment = CloudAssignment.fromJson(value);
                if (assignment.tagId != key) {
                  throw const FormatException('cloud_protocol');
                }
                return MapEntry(key, assignment);
              }),
            ),
      localOnlyTagIds: _ids(json['localOnlyTagIds']),
      retainLocalNote: jsonBool(json['retainLocalNote']),
      observedVersion: json['observedVersion'] == null
          ? null
          : fieldVersion(json['observedVersion']),
      quotaBlocked: json['quotaBlocked'] == null
          ? false
          : jsonBool(json['quotaBlocked']),
    );
  }

  Map<String, Object?> toJson() => {
    'localId': localId,
    'favorite': favorite?.toJson(),
    'note': note?.toJson(),
    'assignments': assignments?.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'localOnlyTagIds': localOnlyTagIds.toList(),
    'retainLocalNote': retainLocalNote,
    'observedVersion': observedVersion,
    'quotaBlocked': quotaBlocked,
  };
}

Set<String> _ids(Object? value) =>
    Set.unmodifiable(jsonList(value).map(jsonString));
