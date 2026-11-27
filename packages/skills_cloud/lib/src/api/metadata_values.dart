import 'cloud_values.dart';

int fieldVersion(Object? value) {
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('cloud_protocol');
  }
  return value;
}

final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
String metadataId(Object? value) {
  final id = jsonString(value);
  if (_id.matchAsPrefix(id)?.end != id.length) {
    throw const FormatException('cloud_protocol');
  }
  return id;
}

bool jsonBool(Object? value) {
  if (value is! bool) throw const FormatException('cloud_protocol');
  return value;
}

final class CloudFavorite {
  const CloudFavorite(this.value, this.version);
  final bool value;
  final int version;

  factory CloudFavorite.fromJson(Object? value) {
    final json = jsonObject(value);
    return CloudFavorite(
      jsonBool(json['value']),
      fieldVersion(json['version']),
    );
  }

  Map<String, Object?> toJson() => {'value': value, 'version': version};
}

final class CloudNoteDevice {
  const CloudNoteDevice(this.name, this.platform);
  final String? name, platform;

  factory CloudNoteDevice.fromJson(Object? value) {
    final json = jsonObject(value);
    _requireFields(json, const ['name', 'platform']);
    return CloudNoteDevice(
      nullableString(json['name']),
      nullableString(json['platform']),
    );
  }

  Map<String, Object?> toJson() => {'name': name, 'platform': platform};
}

final class CloudNoteCandidate {
  const CloudNoteCandidate(this.text, this.device);
  final String? text;
  final CloudNoteDevice? device;

  factory CloudNoteCandidate.fromJson(Object? value) {
    final json = jsonObject(value);
    _requireFields(json, const ['text', 'device']);
    return CloudNoteCandidate(
      nullableString(json['text']),
      json['device'] == null ? null : CloudNoteDevice.fromJson(json['device']),
    );
  }

  Map<String, Object?> toJson() => {'text': text, 'device': device?.toJson()};
}

final class CloudNoteConflict {
  const CloudNoteConflict(this.accepted, this.incoming);
  final CloudNoteCandidate accepted, incoming;

  bool contains(String? value) =>
      accepted.text == value || incoming.text == value;

  factory CloudNoteConflict.fromJson(Object? value) {
    final json = jsonObject(value);
    return CloudNoteConflict(
      CloudNoteCandidate.fromJson(json['accepted']),
      CloudNoteCandidate.fromJson(json['incoming']),
    );
  }

  Map<String, Object?> toJson() => {
    'accepted': accepted.toJson(),
    'incoming': incoming.toJson(),
  };
}

final class CloudNote {
  const CloudNote(this.value, this.version, {this.device, this.conflict});
  final String? value;
  final int version;
  final CloudNoteDevice? device;
  final CloudNoteConflict? conflict;

  factory CloudNote.fromJson(Object? value) {
    final json = jsonObject(value);
    _requireFields(json, const ['value', 'device', 'conflict']);
    return CloudNote(
      nullableString(json['value']),
      fieldVersion(json['version']),
      device: json['device'] == null
          ? null
          : CloudNoteDevice.fromJson(json['device']),
      conflict: json['conflict'] == null
          ? null
          : CloudNoteConflict.fromJson(json['conflict']),
    );
  }

  Map<String, Object?> toJson() => {
    'value': value,
    'version': version,
    'device': device?.toJson(),
    'conflict': conflict?.toJson(),
  };
}

final class CloudAssignment {
  const CloudAssignment(this.tagId, this.assigned, this.version);
  final String tagId;
  final bool assigned;
  final int version;

  factory CloudAssignment.fromJson(Object? value) {
    final json = jsonObject(value);
    return CloudAssignment(
      metadataId(json['tagId']),
      jsonBool(json['assigned']),
      fieldVersion(json['version']),
    );
  }

  Map<String, Object?> toJson() => {
    'tagId': tagId,
    'assigned': assigned,
    'version': version,
  };
}

final class LineageMetadata {
  LineageMetadata({
    required this.lineageId,
    required this.version,
    required this.favorite,
    required this.note,
    required this.assignmentVersion,
    required Map<String, CloudAssignment> assignments,
  }) : assignments = Map.unmodifiable(assignments);

  final String lineageId;
  final int version, assignmentVersion;
  final CloudFavorite favorite;
  final CloudNote note;
  final Map<String, CloudAssignment> assignments;

  factory LineageMetadata.fromJson(Object? value) {
    final json = jsonObject(value),
        assignmentSet = jsonObject(json['assignments']);
    final assignments = <String, CloudAssignment>{};
    for (final item in jsonList(assignmentSet['items'])) {
      final entry = jsonObject(item), id = metadataId(entry['tagId']);
      if (assignments.containsKey(id)) {
        throw const FormatException('cloud_protocol');
      }
      assignments[id] = CloudAssignment(
        id,
        true,
        fieldVersion(entry['version']),
      );
    }
    return LineageMetadata(
      lineageId: metadataId(json['lineageId']),
      version: fieldVersion(json['version']),
      favorite: CloudFavorite.fromJson(json['favorite']),
      note: CloudNote.fromJson(json['note']),
      assignmentVersion: fieldVersion(assignmentSet['version']),
      assignments: assignments,
    );
  }

  Map<String, Object?> toJson() => {
    'lineageId': lineageId,
    'version': version,
    'favorite': favorite.toJson(),
    'note': note.toJson(),
    'assignments': {
      'version': assignmentVersion,
      'items': [
        for (final assignment in assignments.values)
          {'tagId': assignment.tagId, 'version': assignment.version},
      ],
    },
  };
}

final class CloudTag {
  const CloudTag({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.color,
    required this.version,
    required this.nameVersion,
    required this.colorVersion,
  });
  final String id, name, normalizedName;
  final String? color;
  final int version, nameVersion, colorVersion;

  factory CloudTag.fromJson(Object? value) {
    final json = jsonObject(value);
    _requireFields(json, const ['color']);
    final name = jsonString(json['name']),
        normalized = jsonString(json['normalizedName']),
        color = nullableString(json['color']);
    if (name.isEmpty ||
        normalized.isEmpty ||
        (color != null && !RegExp(r'^#[0-9A-F]{6}$').hasMatch(color))) {
      throw const FormatException('cloud_protocol');
    }
    return CloudTag(
      id: metadataId(json['tagId']),
      name: name,
      normalizedName: normalized,
      color: color,
      version: fieldVersion(json['version']),
      nameVersion: fieldVersion(json['nameVersion']),
      colorVersion: fieldVersion(json['colorVersion']),
    );
  }

  Map<String, Object?> toJson() => {
    'tagId': id,
    'name': name,
    'normalizedName': normalizedName,
    'color': color,
    'version': version,
    'nameVersion': nameVersion,
    'colorVersion': colorVersion,
  };
}

final class TagVocabulary {
  TagVocabulary(this.version, Iterable<CloudTag> tags)
    : tags = Map.unmodifiable({for (final tag in tags) tag.id: tag});
  final int version;
  final Map<String, CloudTag> tags;

  factory TagVocabulary.fromJson(Object? value) {
    final json = jsonObject(value);
    final tags = jsonList(json['tags']).map(CloudTag.fromJson).toList();
    if (tags.map((tag) => tag.id).toSet().length != tags.length) {
      throw const FormatException('cloud_protocol');
    }
    return TagVocabulary(fieldVersion(json['version']), tags);
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'tags': [for (final tag in tags.values) tag.toJson()],
  };
}

enum MetadataLimit { note, name, vocabulary }

void _requireFields(Map<String, Object?> json, List<String> fields) {
  if (!fields.every(json.containsKey)) {
    throw const FormatException('cloud_protocol');
  }
}
