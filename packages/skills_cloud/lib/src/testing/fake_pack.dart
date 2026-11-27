import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../api/cloud_values.dart';

/// Test-only pack format. Never accepted by a real Cloud service or Workspace.
final class FakeCommit {
  FakeCommit({
    required this.id,
    required List<String> parents,
    required Map<String, String> files,
  }) : parents = List.unmodifiable(parents),
       files = Map.unmodifiable(files);
  final String id;
  final List<String> parents;
  final Map<String, String> files;
  Map<String, Object?> toJson() => {
    'id': id,
    'parents': parents,
    'files': files,
  };
}

final class FakePack {
  FakePack(Iterable<FakeCommit> commits, Map<String, String> blobs)
    : commits = {for (final c in commits) c.id: c},
      blobs = Map.of(blobs);
  final Map<String, FakeCommit> commits;
  final Map<String, String> blobs;
  List<int> encode() => utf8.encode(
    jsonEncode({
      'commits': commits.values.map((c) => c.toJson()).toList(),
      'blobs': blobs,
    }),
  );
  factory FakePack.decode(List<int> bytes) {
    final m = jsonObject(jsonDecode(utf8.decode(bytes)));
    final blobs = jsonObject(m['blobs'])
        .map((k, v) => MapEntry(k, jsonString(v)));
    for (final entry in blobs.entries) {
      if (sha256.convert(utf8.encode(entry.value)).toString() != entry.key) {
        throw const FormatException('fake_blob');
      }
    }
    final commits = jsonList(m['commits']).map((value) {
      final c = jsonObject(value), id = jsonString(c['id']);
      revision(id);
      final parents = jsonList(c['parents']).map(jsonString).toList();
      parents.forEach(revision);
      final files = jsonObject(c['files'])
          .map((k, v) => MapEntry(k, jsonString(v)));
      if (files.values.any((digest) => !blobs.containsKey(digest))) {
        throw const FormatException('fake_blob');
      }
      return FakeCommit(id: id, parents: parents, files: files);
    }).toList();
    final result = FakePack(commits, blobs);
    if (result.commits.length != commits.length) {
      throw const FormatException('fake_duplicate');
    }
    return result;
  }
  bool containsClosure(Iterable<String> roots) {
    final seen = <String>{}, pending = roots.toList();
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!seen.add(id)) continue;
      final c = commits[id];
      if (c == null) return false;
      pending.addAll(c.parents);
    }
    return true;
  }

  bool descends(String child, String ancestor) {
    final seen = <String>{}, pending = [child];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (id == ancestor) return true;
      if (seen.add(id)) pending.addAll(commits[id]?.parents ?? []);
    }
    return false;
  }
}
