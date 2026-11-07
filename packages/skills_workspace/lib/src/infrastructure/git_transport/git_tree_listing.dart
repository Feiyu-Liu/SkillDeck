import 'dart:convert';

import 'git_source_transport.dart';
import 'git_transport_result.dart';

/// Parses `git ls-tree -r -z --full-tree` records into Source tree entries.
///
/// Every Git Source transport emits this record shape so that one set of
/// rules decides which entries a Source may contain: regular files, executable
/// files, symbolic links, and gitlinks; unsupported modes are rejected, paths
/// must be UTF-8 and inside [repositorySubpath], and at most
/// [maximumRepositoryEntryCount] repository entries are accepted (independent of Skill limits). Paths stay repository-relative so
/// a selection may name a link itself.
GitTransportResult<List<GitTreeEntry>> parseGitTreeListing(
  List<int> bytes, {
  required String repositorySubpath,
  required int maximumRepositoryEntryCount,
}) {
  final entries = <GitTreeEntry>[];
  var start = 0;
  while (start < bytes.length) {
    final end = bytes.indexOf(0, start);
    if (end < 0) return _invalidTree('missingTreeTerminator');
    final record = bytes.sublist(start, end);
    final tab = record.indexOf(0x09);
    if (tab < 0) return _invalidTree('invalidTreeRecord');
    String metadata;
    String fullPath;
    try {
      metadata = ascii.decode(record.sublist(0, tab));
      fullPath = utf8.decode(record.sublist(tab + 1), allowMalformed: false);
    } on FormatException {
      return _invalidTree('treePathNotUtf8');
    }
    final fields = metadata.split(' ');
    if (fields.length != 3 || !isGitObjectId(fields[2])) {
      return _invalidTree('invalidTreeRecord');
    }
    final mode = fields[0];
    final isGitlink = mode == '160000' && fields[1] == 'commit';
    if (!isGitlink &&
        (fields[1] != 'blob' ||
            (mode != '100644' && mode != '100755' && mode != '120000'))) {
      return _invalidTree(
        mode == '160000' ? 'gitlinkNotAllowed' : 'unsupportedTreeEntry',
      );
    }
    if (!_isWithinSelection(fullPath, repositorySubpath)) {
      return _invalidTree('treePathOutsideSelection');
    }
    entries.add(
      GitTreeEntry(
        relativePath: fullPath,
        objectId: fields[2],
        kind: isGitlink
            ? GitTreeEntryKind.gitlink
            : mode == '120000'
            ? GitTreeEntryKind.symbolicLink
            : GitTreeEntryKind.blob,
        executable: mode == '100755',
      ),
    );
    if (entries.length > maximumRepositoryEntryCount) {
      return GitTransportFailure(
        code: GitTransportFailureCode.invalidOutput,
        context: {
          'reason': 'repositoryEntryLimitExceeded',
          'actual': entries.length,
          'actualIsLowerBound': true,
          'maximumRepositoryEntryCount': maximumRepositoryEntryCount,
        },
      );
    }
    start = end + 1;
  }
  entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return GitTransportSuccess(List<GitTreeEntry>.unmodifiable(entries));
}

/// Whether [value] is a full SHA-1 or SHA-256 object ID in lowercase hex.
bool isGitObjectId(String value) =>
    RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(value);

bool _isWithinSelection(String path, String subpath) =>
    subpath.isEmpty || path == subpath || path.startsWith('$subpath/');

GitTransportFailure<List<GitTreeEntry>> _invalidTree(String reason) =>
    GitTransportFailure<List<GitTreeEntry>>(
      code: GitTransportFailureCode.invalidOutput,
      context: <String, Object?>{'reason': reason},
    );
