import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/git_environment.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_environment_probe.dart';
import 'package:skills_workspace/src/infrastructure/source/application_source_adapters.dart';

Future<void> main() async {
  try {
    await Process.run('git', const <String>['--version']);
    stderr.writeln('system Git unexpectedly remained discoverable');
    exitCode = 10;
    return;
  } on ProcessException {
    // Expected: the parent process provides an empty PATH directory.
  }

  // The host probe must classify a missing Git rather than throw, and it must
  // stay a thing callers opt into: nothing below acquires a Source through it.
  final report = await const SystemGitEnvironmentProbe().probe();
  if (report.status != GitEnvironmentStatus.notInstalled) {
    stderr.writeln('Git environment probe misread an empty PATH');
    exitCode = 13;
    return;
  }

  final temporary = await Directory.systemTemp.createTemp(
    'skills-workspace-no-system-git-',
  );
  try {
    final sourceRoot = Directory(path.join(temporary.path, 'source'));
    await sourceRoot.create();
    await File(path.join(sourceRoot.path, 'SKILL.md')).writeAsString(
      '---\nname: local-skill\ndescription: Local\n---\n# Local\n',
    );
    await File(path.join(sourceRoot.path, 'guide.md')).writeAsString('# Guide');
    final acquired = await LocalApplicationSourceAdapter().acquireLocal(
      LocalSourceDescriptor(locator: sourceRoot.path),
      selectedSkillNames: const <String>{},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );
    if (acquired.valueOrNull?.skills.single.slotKey != 'local-skill') {
      stderr.writeln('Local Source acquisition failed without system Git');
      exitCode = 11;
      return;
    }
    if (acquired.valueOrNull!.skills.single.tree.files.length != 2) {
      stderr.writeln('Local content normalization failed without system Git');
      exitCode = 12;
    }
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}
