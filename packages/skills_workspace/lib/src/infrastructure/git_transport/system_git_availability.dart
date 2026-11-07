import 'dart:io';

import 'package:path/path.dart' as path;

/// Reports whether system Git can run, without running it.
abstract interface class SystemGitAvailability {
  Future<bool> isAvailable();
}

/// Looks for a Git executable on `PATH` without executing it.
///
/// On macOS, `/usr/bin/git` is a shim that opens the Command Line Developer
/// Tools installer when the tools are missing (ADR-0101). It counts as
/// available only when `xcode-select -p` names a developer directory that
/// contains Git, so checking availability never triggers that dialog.
final class PathSystemGitAvailability implements SystemGitAvailability {
  PathSystemGitAvailability({
    Map<String, String>? environment,
    bool? isWindows,
    bool? isMacOS,
    bool Function(String path)? fileExists,
    Future<String?> Function()? developerDirectory,
  }) : _environment = environment ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _fileExists = fileExists ?? ((value) => File(value).existsSync()),
       _developerDirectory = developerDirectory ?? _xcodeSelectPath;

  static const macOSShim = '/usr/bin/git';

  final Map<String, String> _environment;
  final bool _isWindows;
  final bool _isMacOS;
  final bool Function(String path) _fileExists;
  final Future<String?> Function() _developerDirectory;

  @override
  Future<bool> isAvailable() async {
    final names = _isWindows
        ? const <String>['git.exe', 'git.cmd', 'git.bat']
        : const <String>['git'];
    final pathContext = _isWindows ? path.windows : path.posix;
    for (final directory in _searchPath()) {
      for (final name in names) {
        final candidate = pathContext.join(directory, name);
        if (!_fileExists(candidate)) continue;
        if (_isMacOS && pathContext.normalize(candidate) == macOSShim) {
          if (await _developerToolsProvideGit()) return true;
          continue;
        }
        return true;
      }
    }
    return false;
  }

  Iterable<String> _searchPath() {
    String? value;
    for (final entry in _environment.entries) {
      if (entry.key == 'PATH' ||
          (_isWindows && entry.key.toUpperCase() == 'PATH')) {
        value = entry.value;
        break;
      }
    }
    return (value ?? '')
        .split(_isWindows ? ';' : ':')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty);
  }

  Future<bool> _developerToolsProvideGit() async {
    try {
      final directory = (await _developerDirectory())?.trim();
      if (directory == null || directory.isEmpty) return false;
      return _fileExists(path.posix.join(directory, 'usr', 'bin', 'git'));
    } on Object {
      return false;
    }
  }
}

Future<String?> _xcodeSelectPath() async {
  final result = await Process.run('/usr/bin/xcode-select', const <String>[
    '-p',
  ]).timeout(const Duration(seconds: 5));
  return result.exitCode == 0 ? result.stdout as String : null;
}
