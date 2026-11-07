import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/source/application_source_adapters.dart';
import 'package:skills_workspace/src/infrastructure/source/git_application_source_adapter.dart';
import 'package:test/test.dart';

const sourceAliasRealPath = 'skills/demo';
const sourceAliasLinkPath = 'plugins/building/skills/demo';
const sourceAliasSkillBody =
    '---\nname: demo\ndescription: Demo\n---\n# Demo\n';

/// A Local and Git Source whose plugin directory links alias one Skill.
///
/// Git link entries are written explicitly so that system Git and Windows
/// links agree on POSIX targets.
final class SourceAliasFixture {
  SourceAliasFixture._(this.root, this.links);
  final Directory root;
  final Map<String, String> links;
  final coordinator = SourceAcquisitionCoordinator(
    local: LocalApplicationSourceAdapter(),
    git: GitApplicationSourceAdapter(transport: SystemGitSourceTransport()),
    wellKnown: WellKnownApplicationSourceAdapter(),
  );

  static Future<SourceAliasFixture> create({
    String target = sourceAliasRealPath,
    String? aliasTarget,
    Map<String, String> extraFiles = const {},
    Map<String, String> extraLinks = const {},
    List<Map<String, Object?>> extraPlugins = const [],
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'source-alias-contract-',
    );
    addTearDown(() => root.delete(recursive: true));
    final links = {
      sourceAliasLinkPath:
          aliasTarget ??
          p.posix.relative(target, from: p.posix.dirname(sourceAliasLinkPath)),
      ...extraLinks,
    };
    final fixture = SourceAliasFixture._(root, links);
    final files = {
      '$target/SKILL.md': sourceAliasSkillBody,
      '.claude-plugin/marketplace.json': jsonEncode({
        'plugins': [
          {
            'name': 'building',
            'source': './plugins/building',
            'skills': ['./skills/demo'],
          },
          ...extraPlugins,
        ],
      }),
      ...extraFiles,
    };
    for (final entry in files.entries) {
      final file = File(p.joinAll([root.path, ...p.posix.split(entry.key)]));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    for (final entry in links.entries) {
      final link = Link(p.joinAll([root.path, ...p.posix.split(entry.key)]));
      await link.parent.create(recursive: true);
      await link.create(p.joinAll(p.posix.split(entry.value)));
    }
    await fixture.git(['init', '--initial-branch=main']);
    await fixture.git(['config', 'core.symlinks', 'true']);
    await fixture.commit();
    return fixture;
  }

  SourceDescriptor source(bool git) => git
      ? GitSourceDescriptor(locator: root.path)
      : LocalSourceDescriptor(locator: root.path);

  Future<SourceAcquisitionResult<AcquiredSource>> acquire({
    required bool git,
    Set<String> names = const {},
    bool fullDepth = false,
  }) => coordinator.acquire(
    source: source(git),
    selectedSkillNames: names,
    options: SourceAcquisitionOptions(fullDepth: fullDepth),
  );

  Future<void> commit() async {
    await git(['add', '.']);
    // Native Windows links use backslashes, while Git stores POSIX targets.
    // Write the index entries explicitly so both transports see one fixture.
    for (final entry in links.entries) {
      final linkPath = p.joinAll([root.path, ...p.posix.split(entry.key)]);
      if (await FileSystemEntity.type(linkPath, followLinks: false) !=
          FileSystemEntityType.link) {
        continue;
      }
      final targetFile = File(p.join(root.path, '.git', 'fixture-link-target'));
      await targetFile.writeAsString(entry.value);
      final object = await git(['hash-object', '-w', targetFile.path]);
      await git([
        'update-index',
        '--add',
        '--cacheinfo',
        '120000,$object,${entry.key}',
      ]);
    }
    await git([
      '-c',
      'user.name=Source Test',
      '-c',
      'user.email=test@example.invalid',
      '-c',
      'commit.gpgsign=false',
      '-c',
      'core.hooksPath=${p.join(root.path, '.no-hooks')}',
      'commit',
      '-m',
      'fixture',
    ]);
  }

  Future<String> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: root.path);
    if (result.exitCode != 0) {
      throw StateError(
        'Fixture Git ${args.first} failed (${result.exitCode}).',
      );
    }
    return (result.stdout as String).trim();
  }
}
