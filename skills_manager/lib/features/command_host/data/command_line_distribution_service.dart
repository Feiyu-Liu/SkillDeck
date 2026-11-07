import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import 'command_line_distribution.dart';

const skillDeckAgentSkillAsset = 'assets/agent_skill/skilldeck/SKILL.md';

/// App-owned distribution files, independent of Workspace transactions.
/// All locations and asset bytes are injected, including in tests.
final class CommandLineDistributionService {
  CommandLineDistributionService({
    required this.rootDirectory,
    required this.bundledExecutable,
    required this.isWindows,
    required this.loadSkill,
    required this.diagnostics,
    Future<void> Function(File)? prepareExecutable,
  }) : _prepareExecutable = prepareExecutable ?? _makeExecutable;

  final String rootDirectory;
  final String bundledExecutable;
  final bool isWindows;
  final Future<List<int>> Function() loadSkill;
  final AppDiagnostics diagnostics;
  final Future<void> Function(File) _prepareExecutable;
  Future<CommandLineToolState>? _tool;
  Future<String>? _source;

  String get toolPath =>
      p.join(rootDirectory, 'bin', isWindows ? 'skilldeck.exe' : 'skilldeck');
  String get sourceDirectory =>
      p.join(rootDirectory, 'agent-skill', 'skilldeck');

  Future<CommandLineToolState> ensureTool() => _tool ??= _ensureTool();

  Future<CommandLineToolState> _ensureTool() async {
    var status = CommandLineToolStatus.failed;
    try {
      final bundled = File(bundledExecutable);
      if (!await bundled.exists()) {
        status = CommandLineToolStatus.notBundled;
      } else {
        await ensurePrivateDirectory(rootDirectory);
        await ensurePrivateDirectory(p.dirname(toolPath));
        final target = File(toolPath);
        if (await target.exists() &&
            await _hash(target) == await _hash(bundled)) {
          await _prepareExecutable(target);
        } else {
          final staging = await Directory(p.dirname(toolPath))
              .createTemp('.skilldeck-tool-');
          try {
            await ensurePrivateDirectory(staging.path);
            final staged = await bundled.copy(
              p.join(staging.path, 'skilldeck'),
            );
            await _prepareExecutable(staged);
            // File.rename replaces the destination on supported desktop OSes.
            // No operation removes the previous copy before this commit point.
            await staged.rename(toolPath);
          } finally {
            await staging.delete(recursive: true);
          }
        }
        status = CommandLineToolStatus.ready;
      }
    } on Object {
      // Filesystem/process errors can contain paths; expose only the status.
    }
    diagnostics.info('commandLine.tool', context: {'status': status.name});
    return CommandLineToolState(status: status, path: toolPath);
  }

  /// Once per launch; upgrades change the ordinary local Source bytes only.
  Future<String> ensureAgentSkillSource() => _source ??= _ensureSource();

  Future<String> _ensureSource() async {
    final bytes = await loadSkill();
    final target = File(p.join(sourceDirectory, 'SKILL.md'));
    if (await target.exists() &&
        await _hash(target) == sha256.convert(bytes).toString()) {
      return sourceDirectory;
    }
    await ensurePrivateDirectory(rootDirectory);
    final parent = p.dirname(sourceDirectory);
    await ensurePrivateDirectory(parent);
    final staging = await Directory(parent).createTemp('.skilldeck-source-');
    try {
      await ensurePrivateDirectory(staging.path);
      final next = await Directory(p.join(staging.path, 'next')).create();
      await File(p.join(next.path, 'SKILL.md'))
          .writeAsBytes(bytes, flush: true);
      final previous = Directory(sourceDirectory);
      Directory? backup;
      if (await previous.exists()) {
        backup = await previous.rename(p.join(staging.path, 'previous'));
      }
      try {
        await next.rename(sourceDirectory);
      } on Object {
        await backup?.rename(sourceDirectory);
        rethrow;
      }
    } finally {
      await staging.delete(recursive: true);
    }
    return sourceDirectory;
  }
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _makeExecutable(File file) async {
  if (Platform.isWindows) return;
  final result = await Process.run('/bin/chmod', ['755', file.path]);
  if (result.exitCode != 0) {
    throw const FileSystemException('Cannot prepare command-line tool.');
  }
}
