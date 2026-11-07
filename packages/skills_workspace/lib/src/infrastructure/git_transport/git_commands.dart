import 'dart:convert';

import 'git_source_parser.dart';

final class GitCommand {
  GitCommand({
    required this.executable,
    required List<String> arguments,
    Map<String, String> environment = const {},
    this.workingDirectory,
    List<int> stdinBytes = const [],
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment),
       stdinBytes = List.unmodifiable(stdinBytes) {
    if (executable.trim().isEmpty) {
      throw ArgumentError.value(executable, 'executable', 'must not be empty');
    }
  }

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final List<int> stdinBytes;
}

final class GitEnvironmentPolicy {
  const GitEnvironmentPolicy();

  Map<String, String> apply(Map<String, String> inherited) {
    final environment = <String, String>{...inherited};
    environment['GIT_TERMINAL_PROMPT'] = '0';
    environment['GCM_INTERACTIVE'] = 'Never';
    environment['GIT_LFS_SKIP_SMUDGE'] = '1';
    environment['SSH_ASKPASS_REQUIRE'] = 'never';
    environment.putIfAbsent('GIT_SSH_COMMAND', () => 'ssh -o BatchMode=yes');
    return Map.unmodifiable(environment);
  }
}

/// Builds argv-only commands for a bare Git source object database, plus the
/// host capability probe that reports whether that executable is usable.
///
/// No command creates or updates a working tree. Caller-provided locators and
/// refs occur only after an argv `--` terminator.
///
/// The probe shares this builder so it resolves the same [executable] the
/// transport does; probing a different binary would let the capability check
/// report success while every acquisition still fails.
final class GitBareCommandBuilder {
  const GitBareCommandBuilder({this.executable = 'git'});

  final String executable;

  /// Reports the executable's version without touching any repository.
  GitCommand version({required Map<String, String> environment}) => GitCommand(
    executable: executable,
    arguments: const ['--version'],
    environment: environment,
  );

  GitCommand initialize({
    required String repositoryPath,
    required String disabledHooksPath,
    required Map<String, String> environment,
  }) => GitCommand(
    executable: executable,
    arguments: [
      '-c',
      'init.templateDir=${_requireNonEmpty(disabledHooksPath, 'disabledHooksPath')}',
      'init',
      '--bare',
      '--',
      _requireNonEmpty(repositoryPath, 'repositoryPath'),
    ],
    environment: environment,
  );

  GitCommand fetch({
    required String repositoryPath,
    required String disabledHooksPath,
    required String locator,
    String? ref,
    required Map<String, String> environment,
  }) => GitCommand(
    executable: executable,
    arguments: [
      '-C',
      _requireNonEmpty(repositoryPath, 'repositoryPath'),
      '-c',
      'core.hooksPath=${_requireNonEmpty(disabledHooksPath, 'disabledHooksPath')}',
      '-c',
      'filter.lfs.required=false',
      '-c',
      'filter.lfs.smudge=',
      '-c',
      'filter.lfs.clean=',
      '-c',
      'filter.lfs.process=',
      'fetch',
      '--depth',
      '1',
      '--no-tags',
      '--recurse-submodules=no',
      '--',
      _requireCanonicalLocator(locator),
      ?_requireOptionalNonEmpty(ref, 'ref'),
    ],
    environment: environment,
  );

  GitCommand resolveFetchedCommit({
    required String repositoryPath,
    required String disabledHooksPath,
    required Map<String, String> environment,
  }) => _repositoryCommand(
    repositoryPath: repositoryPath,
    disabledHooksPath: disabledHooksPath,
    environment: environment,
    arguments: const ['rev-parse', '--verify', 'FETCH_HEAD^{commit}'],
  );

  GitCommand listTree({
    required String repositoryPath,
    required String disabledHooksPath,
    required String objectId,
    String repositorySubpath = '',
    required Map<String, String> environment,
  }) {
    _requireObjectId(objectId);
    _requireSafeSubpath(repositorySubpath);
    return _repositoryCommand(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      environment: environment,
      arguments: [
        'ls-tree',
        '-r',
        '-rz',
        '--full-tree',
        objectId,
        if (repositorySubpath.isNotEmpty) ...['--', repositorySubpath],
      ],
    );
  }

  GitCommand catFileBatch({
    required String repositoryPath,
    required String disabledHooksPath,
    required Map<String, String> environment,
    List<String> objectIds = const [],
  }) {
    for (final objectId in objectIds) {
      _requireObjectId(objectId);
    }
    return _repositoryCommand(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      environment: environment,
      arguments: const ['cat-file', '--batch'],
      stdinBytes: objectIds.isEmpty
          ? const []
          : utf8.encode('${objectIds.join('\n')}\n'),
    );
  }

  GitCommand _repositoryCommand({
    required String repositoryPath,
    required String disabledHooksPath,
    required Map<String, String> environment,
    required List<String> arguments,
    List<int> stdinBytes = const [],
  }) => GitCommand(
    executable: executable,
    arguments: [
      '-C',
      _requireNonEmpty(repositoryPath, 'repositoryPath'),
      '-c',
      'core.hooksPath=${_requireNonEmpty(disabledHooksPath, 'disabledHooksPath')}',
      ...arguments,
    ],
    environment: environment,
    stdinBytes: stdinBytes,
  );
}

final class GitHelperCommand {
  GitHelperCommand(this.executable, List<String> arguments)
    : arguments = List.unmodifiable(arguments);

  final String executable;
  final List<String> arguments;
}

final class GitProcessTreeCommands {
  const GitProcessTreeCommands._();

  static GitHelperCommand windowsTaskkill(int processId) =>
      GitHelperCommand('taskkill', ['/PID', '$processId', '/T', '/F']);

  static GitHelperCommand posixProcessTable() =>
      GitHelperCommand('ps', const ['-eo', 'pid=,ppid=']);
}

void _requireObjectId(String value) {
  if (!RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(value)) {
    throw ArgumentError.value(value, 'objectId', 'must be a Git object ID');
  }
}

void _requireSafeSubpath(String value) {
  if (value.isEmpty) {
    return;
  }
  if (value.startsWith('/') ||
      value.startsWith(r'\') ||
      value.contains(r'\') ||
      value.split('/').any((part) => part.isEmpty || part == '..')) {
    throw ArgumentError.value(
      value,
      'repositorySubpath',
      'must be a normalized POSIX relative path',
    );
  }
}

String _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return value;
}

String? _requireOptionalNonEmpty(String? value, String name) =>
    value == null ? null : _requireNonEmpty(value, name);

String _requireCanonicalLocator(String locator) {
  final parsed = const GitSourceParser().parse(locator).valueOrNull;
  if (parsed == null || parsed.locator != locator) {
    throw ArgumentError.value(
      locator,
      'locator',
      'must be a canonical credential-free Git locator',
    );
  }
  return locator;
}
