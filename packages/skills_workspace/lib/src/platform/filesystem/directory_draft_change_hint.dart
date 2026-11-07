import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/ports/draft_change_hint_ports.dart';

typedef DraftDirectoryWatch =
    Stream<FileSystemEvent> Function(String directoryPath);

/// `Directory.watch` adapter used only to schedule authoritative Draft rescans.
final class DirectoryDraftChangeHintPort implements DraftChangeHintPort {
  DirectoryDraftChangeHintPort({DraftDirectoryWatch? directoryWatch})
    : _directoryWatch = directoryWatch ?? _watchDirectory;

  final DraftDirectoryWatch _directoryWatch;

  @override
  Stream<DraftChangeHint> watchDraft(String draftPath) {
    final normalized = path.normalize(path.absolute(draftPath));
    return _directoryWatch(normalized).map((_) => const DraftChangeHint());
  }
}

Stream<FileSystemEvent> _watchDirectory(String directoryPath) =>
    Directory(directoryPath).watch(recursive: true);
