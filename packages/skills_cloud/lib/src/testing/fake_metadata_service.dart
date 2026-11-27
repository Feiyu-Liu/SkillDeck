part of 'fake_cloud_service.dart';

extension on FakeCloudService {
  http.Response _metadataRoute(
    _Account account,
    http.Request request,
    String deviceName,
    Map<String, Object?> Function() body,
  ) {
    final path = request.url.pathSegments, method = request.method;
    if (path[1] == 'tags') {
      return _tagRoute(account, path.skip(2).toList(), method, body);
    }
    final lineage = account.lineages[path[2]];
    if (lineage == null) return _json({'error': 'notFound'}, 404);
    if (lineage.state != LineageState.live) {
      return _json({
        'error': 'lineageEnded',
        'lineage': lineage.value.toJson(),
      }, 410);
    }
    if (lineage.head == null) return _json({'error': 'notFound'}, 404);
    final metadata = lineage.metadata,
        device = CloudNoteDevice(deviceName, 'macos');
    if (path.length == 4) return _json(metadata.value(lineage.id).toJson());
    if (path[4] == 'favorite') {
      var current = metadata.favorite;
      if (method == 'PUT') {
        final input = body();
        final value = jsonBool(input['value']);
        if (value != current.value) {
          if (input['expectedVersion'] != current.version) {
            return _stale(current.toJson());
          }
          current = metadata.favorite = CloudFavorite(
            value,
            current.version + 1,
          );
          _metadataChanged(account, lineage);
        }
      }
      return _json(current.toJson());
    }
    if (path[4] == 'assignments') {
      final tagId = path[5];
      if (!account.tags.containsKey(tagId)) return _tagEnded(account, tagId);
      var current =
          metadata.assignments[tagId] ?? CloudAssignment(tagId, false, 0);
      if (method == 'PUT') {
        final input = body();
        final value = jsonBool(input['assigned']);
        if (value != current.assigned) {
          if (input['expectedVersion'] != current.version) {
            return _stale(current.toJson());
          }
          current = metadata.assignments[tagId] = CloudAssignment(
            tagId,
            value,
            current.version + 1,
          );
          metadata.assignmentVersion++;
          _metadataChanged(account, lineage);
        }
      }
      return _json(current.toJson());
    }
    if (path[4] != 'note') return _json({'error': 'notFound'}, 404);
    var current = metadata.note;
    if (method != 'GET') {
      final input = body();
      final value = nullableString(input['value'])?.trim();
      if (value == '') throw const FormatException();
      if (value != null && utf8.encode(value).length > 4096) {
        return _json({'error': 'metadataTooLarge', 'field': 'note'}, 413);
      }
      final resolution = path.length == 6 && path[5] == 'resolve';
      final opening = path.length == 6 && path[5] == 'conflicts';
      final old = current.conflict;
      if (old != null && !resolution) {
        return old.contains(value)
            ? _json(current.toJson())
            : _json({
                'error': 'noteConflict',
                'current': current.toJson(),
              }, 409);
      }
      if (old == null && value == current.value) return _json(current.toJson());
      if (input['expectedVersion'] != current.version) {
        return _stale(current.toJson());
      }
      if (resolution && old == null) {
        return _json({
          'error': 'noNoteConflict',
          'current': current.toJson(),
        }, 409);
      }
      current = metadata.note = opening
          ? CloudNote(
              current.value,
              current.version + 1,
              device: current.device,
              conflict: CloudNoteConflict(
                CloudNoteCandidate(current.value, current.device),
                CloudNoteCandidate(value, device),
              ),
            )
          : CloudNote(value, current.version + 1, device: device);
      _metadataChanged(account, lineage);
    }
    return _json(current.toJson());
  }

  http.Response _tagRoute(
    _Account a,
    List<String> path,
    String method,
    Map<String, Object?> Function() body,
  ) {
    if (path.isEmpty) {
      if (method == 'GET') return _json(a.vocabulary.toJson());
      final input = body(), key = jsonString(input['clientKey']);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key) ||
          input['expectedVersion'] != null) {
        throw const FormatException();
      }
      if (a.tagAliases[key] case final id?) {
        final tag = _canonicalTag(a, id);
        return tag == null
            ? _json({'error': 'tagDeleted'}, 410)
            : _json(tag.toJson());
      }
      final name = jsonString(input['name']).trim(),
          normalized = name.toUpperCase();
      if (name.runes.length > 64) {
        return _json({'error': 'metadataTooLarge', 'field': 'name'}, 413);
      }
      if (normalized.isEmpty) throw const FormatException();
      final existing = a.tags.values
          .where((tag) => tag.normalizedName == normalized)
          .firstOrNull;
      if (existing != null) {
        a.tagAliases[key] = existing.id;
        return _json(existing.toJson());
      }
      if (a.tags.length >= maxTags) {
        return _json({'error': 'storageLimitReached'}, 403);
      }
      final tag = CloudTag(
        id: 'tag-${_nextId++}',
        name: name,
        normalizedName: normalized,
        color: nullableString(input['color'])?.toUpperCase(),
        version: 1,
        nameVersion: 1,
        colorVersion: 1,
      );
      a.tags[tag.id] = tag;
      a.tagAliases[key] = tag.id;
      _tagChanged(a);
      return _json(tag.toJson(), 201);
    }

    final id = path.first, tag = a.tags[id];
    if (tag == null) {
      if (path.length == 2 &&
          path[1] == 'delete' &&
          a.endedTags.containsKey(id) &&
          a.endedTags[id] == null) {
        return _json({'tagId': id});
      }
      return _tagEnded(a, id);
    }
    if (method == 'GET') return _json(tag.toJson());
    final input = body(), expected = input['expectedVersion'];
    if (path[1] == 'delete') {
      if (expected != tag.version) return _stale(tag.toJson());
      _endTag(a, id);
      return _json({'tagId': id});
    }
    final rename = path[1] == 'name';
    final name = rename ? jsonString(input['name']).trim() : tag.name;
    final color = rename
        ? tag.color
        : nullableString(input['color'])?.toUpperCase();
    if (name == tag.name && color == tag.color) return _json(tag.toJson());
    if (name.isEmpty) throw const FormatException();
    if (name.runes.length > 64) {
      return _json({'error': 'metadataTooLarge', 'field': 'name'}, 413);
    }
    if (expected != (rename ? tag.nameVersion : tag.colorVersion)) {
      return _stale(tag.toJson());
    }
    final normalized = name.toUpperCase();
    final destination = a.tags.values
        .where((other) => other.id != id && other.normalizedName == normalized)
        .firstOrNull;
    if (destination != null) {
      _endTag(a, id, survivor: destination.id);
      return _json(destination.toJson());
    }
    final changed = a.tags[id] = CloudTag(
      id: id,
      name: name,
      normalizedName: normalized,
      color: color,
      version: tag.version + 1,
      nameVersion: tag.nameVersion + (rename ? 1 : 0),
      colorVersion: tag.colorVersion + (rename ? 0 : 1),
    );
    _tagChanged(a);
    return _json(changed.toJson());
  }

  CloudTag? _canonicalTag(_Account a, String id) {
    String? target = id;
    while (target != null && a.endedTags.containsKey(target)) {
      target = a.endedTags[target];
    }
    return a.tags[target];
  }

  http.Response _tagEnded(_Account a, String id) {
    if (!a.endedTags.containsKey(id)) return _json({'error': 'notFound'}, 404);
    final tag = _canonicalTag(a, id);
    return tag == null
        ? _json({'error': 'tagDeleted'}, 410)
        : _json({'error': 'tagMerged', 'replacementTagId': tag.id}, 410);
  }

  http.Response _stale(Map<String, Object?> current) =>
      _json({'error': 'staleFieldVersion', 'current': current}, 409);

  void _metadataChanged(_Account a, _FakeLineage lineage) {
    lineage.metadata.version++;
    a.feed['metadata:${lineage.id}'] = ++a.sequence;
  }

  void _tagChanged(_Account a) {
    a.tagVersion++;
    a.feed['tagVocabulary:vocabulary'] = ++a.sequence;
  }

  void _endTag(_Account a, String id, {String? survivor}) {
    a.tags.remove(id);
    a.endedTags[id] = survivor;
    _tagChanged(a);
    for (final lineage in a.lineages.values) {
      final metadata = lineage.metadata;
      final source = metadata.assignments.remove(id);
      if (source?.assigned != true) continue;
      if (survivor != null &&
          metadata.assignments[survivor]?.assigned != true) {
        metadata.assignments[survivor] = CloudAssignment(
          survivor,
          true,
          (metadata.assignments[survivor]?.version ?? 0) + 1,
        );
      }
      metadata.assignmentVersion++;
      _metadataChanged(a, lineage);
    }
  }
}

final class _FakeMetadata {
  CloudFavorite favorite = const CloudFavorite(false, 0);
  CloudNote note = const CloudNote(null, 0);
  int version = 0, assignmentVersion = 0;
  final assignments = <String, CloudAssignment>{};

  LineageMetadata value(String lineageId) => LineageMetadata(
    lineageId: lineageId,
    version: version,
    favorite: favorite,
    note: note,
    assignmentVersion: assignmentVersion,
    assignments: {
      for (final value in assignments.values)
        if (value.assigned) value.tagId: value,
    },
  );
}
