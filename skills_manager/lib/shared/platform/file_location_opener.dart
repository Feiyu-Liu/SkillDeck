import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final fileLocationOpenerProvider = Provider<FileLocationOpener>(
  (ref) => const ProcessFileLocationOpener(),
);

abstract interface class FileLocationOpener {
  Future<bool> reveal(String path);
}

final class ProcessFileLocationOpener implements FileLocationOpener {
  const ProcessFileLocationOpener();

  @override
  Future<bool> reveal(String path) async {
    final executable = switch (Platform.operatingSystem) {
      'macos' => 'open',
      'windows' => 'explorer.exe',
      'linux' => 'xdg-open',
      _ => null,
    };
    if (executable == null) return false;
    final arguments = switch (Platform.operatingSystem) {
      'macos' => ['-R', path],
      'windows' => ['/select,$path'],
      'linux' => [p.dirname(path)],
      _ => const <String>[],
    };
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: false,
      );
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
