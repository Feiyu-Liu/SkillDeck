import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether `skilldeck` is reachable from every terminal through a link in a
/// directory that is already on the default macOS PATH (ADR-0111).
enum CommandLinePathLinkStatus {
  notInstalled,

  /// The link points at the stable CLI copy. It never needs repair, because
  /// the App refreshes that copy on every launch.
  installed,

  /// Something else owns the link path. SkillDeck never replaces it.
  conflict,
}

enum CommandLinePathLinkOutcome { succeeded, cancelled, conflict, failed }

abstract interface class CommandLinePathLink {
  String get linkPath;

  Future<CommandLinePathLinkStatus> status();

  Future<CommandLinePathLinkOutcome> install();

  /// Removes only SkillDeck's own link.
  Future<CommandLinePathLinkOutcome> remove();
}

abstract interface class CommandLinePathLinkProcessRunner {
  Future<String?> run(String executable, List<String> arguments);
}

/// Creates `/usr/local/bin/skilldeck → ~/.skilldeck/bin/skilldeck`, asking for
/// administrator rights only when the directory is not writable. Elevation
/// uses the same `osascript` adapter as Agent root ownership repair and
/// migrates with it (issues #12 and #13).
final class MacOsCommandLinePathLink implements CommandLinePathLink {
  MacOsCommandLinePathLink({
    required String targetPath,
    required String userHomePath,
    this.linkPath = '/usr/local/bin/skilldeck',
    CommandLinePathLinkProcessRunner? processRunner,
  }) : _targetPath = p.normalize(targetPath),
       _userHomePath = p.normalize(userHomePath),
       _processRunner = processRunner ?? const _DirectProcessRunner();

  @override
  final String linkPath;
  final String _targetPath;
  final String _userHomePath;
  final CommandLinePathLinkProcessRunner _processRunner;

  @override
  Future<CommandLinePathLinkStatus> status() async {
    final type = await FileSystemEntity.type(linkPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return CommandLinePathLinkStatus.notInstalled;
    }
    if (type != FileSystemEntityType.link) {
      return CommandLinePathLinkStatus.conflict;
    }
    try {
      final target = await Link(linkPath).target();
      return p.normalize(target) == _targetPath
          ? CommandLinePathLinkStatus.installed
          : CommandLinePathLinkStatus.conflict;
    } on FileSystemException {
      return CommandLinePathLinkStatus.conflict;
    }
  }

  @override
  Future<CommandLinePathLinkOutcome> install() async {
    switch (await status()) {
      case CommandLinePathLinkStatus.installed:
        return CommandLinePathLinkOutcome.succeeded;
      case CommandLinePathLinkStatus.conflict:
        return CommandLinePathLinkOutcome.conflict;
      case CommandLinePathLinkStatus.notInstalled:
        break;
    }
    // The root shell receives only a target inside the user's own home.
    if (!p.isAbsolute(_targetPath) || !p.isWithin(_userHomePath, _targetPath)) {
      return CommandLinePathLinkOutcome.failed;
    }
    try {
      await Link(linkPath).create(_targetPath);
      return CommandLinePathLinkOutcome.succeeded;
    } on FileSystemException {
      // Usually a root-owned or missing /usr/local/bin.
    }
    final elevated = await _elevate('install');
    if (elevated == CommandLinePathLinkOutcome.cancelled) return elevated;
    return switch (await status()) {
      CommandLinePathLinkStatus.installed =>
        CommandLinePathLinkOutcome.succeeded,
      CommandLinePathLinkStatus.conflict => CommandLinePathLinkOutcome.conflict,
      CommandLinePathLinkStatus.notInstalled =>
        CommandLinePathLinkOutcome.failed,
    };
  }

  @override
  Future<CommandLinePathLinkOutcome> remove() async {
    switch (await status()) {
      case CommandLinePathLinkStatus.notInstalled:
        return CommandLinePathLinkOutcome.succeeded;
      case CommandLinePathLinkStatus.conflict:
        return CommandLinePathLinkOutcome.conflict;
      case CommandLinePathLinkStatus.installed:
        break;
    }
    try {
      await Link(linkPath).delete();
      return CommandLinePathLinkOutcome.succeeded;
    } on FileSystemException {
      // Fall through to elevation.
    }
    final elevated = await _elevate('remove');
    if (elevated == CommandLinePathLinkOutcome.cancelled) return elevated;
    return await status() == CommandLinePathLinkStatus.notInstalled
        ? CommandLinePathLinkOutcome.succeeded
        : CommandLinePathLinkOutcome.failed;
  }

  Future<CommandLinePathLinkOutcome> _elevate(String action) async {
    final output = await _processRunner.run('/usr/bin/osascript', [
      '-e',
      _pathLinkAppleScript,
      '--',
      action,
      _targetPath,
      linkPath,
      p.dirname(linkPath),
    ]);
    return switch (output?.trim()) {
      'ok' => CommandLinePathLinkOutcome.succeeded,
      'cancelled' => CommandLinePathLinkOutcome.cancelled,
      _ => CommandLinePathLinkOutcome.failed,
    };
  }
}

// Each path passes through `quoted form of`. The existence checks run again as
// root, so a file created after the unprivileged check is never replaced.
const String _pathLinkAppleScript = r'''
on run argv
  if (count of argv) is not 4 then return "invalid"
  set actionName to item 1 of argv
  set targetPath to quoted form of (item 2 of argv)
  set linkPath to quoted form of (item 3 of argv)
  set linkDirectory to quoted form of (item 4 of argv)
  if actionName is "install" then
    set commandText to "/bin/mkdir -p " & linkDirectory & " && [ ! -e " & linkPath & " ] && [ ! -L " & linkPath & " ] && /bin/ln -s " & targetPath & " " & linkPath
  else if actionName is "remove" then
    set commandText to "[ -L " & linkPath & " ] && [ \"$(/usr/bin/readlink " & linkPath & ")\" = " & targetPath & " ] && /bin/rm " & linkPath
  else
    return "invalid"
  end if
  try
    do shell script commandText with administrator privileges
    return "ok"
  on error errorMessage number errorNumber
    if errorNumber is -128 or errorNumber is -60006 then return "cancelled"
    return "failed"
  end try
end run
''';

final class _DirectProcessRunner implements CommandLinePathLinkProcessRunner {
  const _DirectProcessRunner();

  @override
  Future<String?> run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      return result.exitCode == 0 ? '${result.stdout}' : null;
    } on ProcessException {
      return null;
    }
  }
}
