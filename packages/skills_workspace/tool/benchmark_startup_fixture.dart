import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';

/// Measures repository-open on a generated fixture, never a user's Workspace.
///
/// Create: dart run tool/benchmark_startup_fixture.dart --create
/// Reuse:  dart run tool/benchmark_startup_fixture.dart --fixture `<printed-root>`
/// Add --validate to measure one Skill and explicit full validation after open.
Future<void> main(List<String> arguments) async {
  final create = arguments.contains('--create');
  final validate = arguments.contains('--validate');
  final fixtureIndex = arguments.indexOf('--fixture');
  if (create == (fixtureIndex >= 0) ||
      (fixtureIndex >= 0 && fixtureIndex + 1 >= arguments.length)) {
    throw ArgumentError('Choose --create or --fixture <generated-root>.');
  }
  final root = create
      ? await Directory.systemTemp.createTemp('skilldeck-startup-fixture-')
      : Directory(arguments[fixtureIndex + 1]).absolute;
  final marker = File(path.join(root.path, 'startup-fixture.json'));
  if (create) {
    await _seed(root);
    await marker.writeAsString(jsonEncode({'skills': 85, 'agents': 4}));
    stdout.writeln(jsonEncode({'fixtureRoot': root.path}));
    return;
  }
  await verifyStartupFixtureRoot(root);
  final events = <Map<String, Object?>>[];
  final subscription = Logger('skills_workspace.performance').onRecord.listen(
    (record) => events.add(jsonDecode(record.message) as Map<String, Object?>),
  );
  final before = await captureStartupProjectionManifest(root);
  final opens = <int>[];
  final phases = <List<Map<String, Object?>>>[];
  String? catalogHash;
  for (var run = 0; run < 6; run++) {
    final repository = createStartupFixtureRepository(root);
    events.clear();
    final clock = Stopwatch()..start();
    final snapshot = _success(await repository.open().completed);
    clock.stop();
    opens.add(clock.elapsedMicroseconds);
    phases.add(List.of(events));
    if (snapshot.managedSkills.length != 85 ||
        snapshot.managedSkills.expand((skill) => skill.activations).length !=
            340) {
      throw StateError('Fixture catalog counts changed.');
    }
    final hash = _catalogHash(snapshot);
    catalogHash ??= hash;
    if (catalogHash != hash) throw StateError('Authoritative catalog changed.');
    _success(await repository.close().completed);
  }
  final after = await captureStartupProjectionManifest(root);
  final unchanged = jsonEncode(before) == jsonEncode(after);
  if (!unchanged) throw StateError('Startup changed a projection.');
  final validation = <String, Object?>{};
  if (validate) {
    final repository = createStartupFixtureRepository(root);
    final snapshot = _success(await repository.open().completed);
    events.clear();
    final clock = Stopwatch()..start();
    final single = _success(
      await repository
          .validateWorkspace(
            ValidateWorkspaceRequest(
              managedSkillIds: {snapshot.managedSkills.first.id},
            ),
          )
          .completed,
    );
    validation['singleElapsedMicros'] = clock.elapsedMicroseconds;
    validation['singleCheckedSkills'] = single.checkedSkillCount;
    validation['singleEvents'] = List.of(events);
    events.clear();
    clock.reset();
    final full = _success(
      await repository
          .validateWorkspace(const ValidateWorkspaceRequest())
          .completed,
    );
    validation['fullElapsedMicros'] = clock.elapsedMicroseconds;
    validation['fullCheckedSkills'] = full.checkedSkillCount;
    validation['fullHealthySkills'] = full.healthySkillCount;
    validation['fullRepairedArtifacts'] = full.repairedArtifactCount;
    validation['fullEvents'] = List.of(events);
    _success(await repository.close().completed);
    if (_catalogHash(snapshot) != catalogHash ||
        full.healthySkillCount != 85 ||
        jsonEncode(await captureStartupProjectionManifest(root)) !=
            jsonEncode(before)) {
      throw StateError('Validation changed the healthy fixture.');
    }
  }
  await subscription.cancel();
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'operatingSystem': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
      'mode': const bool.fromEnvironment('dart.vm.product')
          ? 'aot-product'
          : 'jit',
      'skills': 85,
      'copyActivations': 340,
      'projectionArtifacts': 425,
      'projectionFiles': before['files'],
      'projectionBytes': before['bytes'],
      'firstOpenMicros': opens.first,
      'warmOpenRunsMicros': opens.skip(1).toList(),
      'warmOpenMedianMicros': (opens.skip(1).toList()..sort())[2],
      'openEvents': phases,
      'catalogSha256': catalogHash,
      'projectionContentSha256': before['contentSha256'],
      'projectionMetadataSha256': before['metadataSha256'],
      'projectionsUnchanged': unchanged,
      'validation': validation,
    }),
  );
}

SkillsRepository createStartupFixtureRepository(Directory root) =>
    createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: path.join(root.path, 'workspace'),
        agentHomePath: path.join(root.path, 'agent-home'),
        additionalAgents: [
          for (var agent = 0; agent < 4; agent++)
            AgentDefinition(
              id: 'startup-agent-$agent',
              displayName: 'Startup fixture agent $agent',
              platforms: {
                _platform: AgentPlatformDefinition(
                  globalSkillsPath: path.join(
                    root.path,
                    'agent-home',
                    'agent-$agent',
                    'skills',
                  ),
                ),
              },
            ),
        ],
      ),
    );

DesktopPlatform get _platform => Platform.isMacOS
    ? DesktopPlatform.macos
    : Platform.isWindows
    ? DesktopPlatform.windows
    : DesktopPlatform.linux;

Future<void> _seed(Directory root) async {
  await Directory(path.join(root.path, 'agent-home')).create();
  final repository = createStartupFixtureRepository(root);
  try {
    _success(await repository.open().completed);
    for (var skill = 0; skill < 85; skill++) {
      final name = 'startup-skill-${skill.toString().padLeft(3, '0')}';
      final source = await Directory(
        path.join(root.path, 'sources', name),
      ).create(recursive: true);
      await File(path.join(source.path, 'SKILL.md')).writeAsString(
        '---\nname: $name\ndescription: Generated startup benchmark fixture.\n---\n# Fixture\n',
      );
      for (var file = 0; file < 9; file++) {
        await File(
          path.join(source.path, 'file-$file.txt'),
        ).writeAsString('fixture-$skill-$file\n' * 1000);
      }
      _success(
        await repository
            .install(
              InstallRequest(
                source: LocalSourceDescriptor(locator: source.path),
                activationSelection: ActivationSelection.explicit([
                  for (var agent = 0; agent < 4; agent++)
                    ActivationTarget(
                      agentId: 'startup-agent-$agent',
                      scope: ActivationScope.global,
                    ),
                ]),
                activationMode: RequestedActivationMode.copy,
              ),
            )
            .completed,
      );
    }
  } finally {
    _success(await repository.close().completed);
  }
}

T _success<T>(SkillsResult<T> result) {
  if (!result.isSuccess) {
    throw StateError(
      'Fixture operation failed: ${result.failureOrNull?.code.name}',
    );
  }
  return result.valueOrNull as T;
}

String _catalogHash(RepositorySnapshot snapshot) {
  final skills = snapshot.managedSkills.toList()
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'revision': snapshot.revision.value,
            'skills': [
              for (final skill in skills)
                {
                  'id': skill.id.value,
                  'hash': skill.currentRevision.contentHash,
                  'activations': [
                    for (final activation in skill.activations)
                      '${activation.agentIds.join(",")}:${activation.location}:${activation.mode.name}',
                  ]..sort(),
                },
            ],
          }),
        ),
      )
      .toString();
}

Future<Map<String, Object>> captureStartupProjectionManifest(
  Directory root,
) async {
  final content = <String, String>{};
  final metadata = <String, String>{};
  var bytes = 0;
  for (final directory in [
    Directory(path.join(root.path, 'workspace', 'repository-copies')),
    Directory(path.join(root.path, 'agent-home')),
  ]) {
    final entries =
        await directory.list(recursive: true, followLinks: false).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final stat = await entry.stat();
      final relative = path.relative(entry.path, from: root.path);
      metadata[relative] =
          '${stat.type}:${stat.mode}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
      if (entry is File) {
        final data = await entry.readAsBytes();
        content[relative] = sha256.convert(data).toString();
        bytes += data.length;
      }
    }
  }
  return {
    'files': content.length,
    'bytes': bytes,
    'contentSha256': sha256
        .convert(utf8.encode(jsonEncode(content)))
        .toString(),
    'metadataSha256': sha256
        .convert(utf8.encode(jsonEncode(metadata)))
        .toString(),
  };
}

/// Rejects regular Workspaces and accepts only this tool's temporary fixtures.
Future<void> verifyStartupFixtureRoot(Directory root) async {
  final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
  final resolvedRoot = await root.resolveSymbolicLinks();
  if (path.dirname(resolvedRoot) != temporaryRoot ||
      !path.basename(resolvedRoot).startsWith('skilldeck-startup-fixture-') ||
      !await File(path.join(root.path, 'startup-fixture.json')).exists()) {
    throw ArgumentError('Only generated temporary fixtures are accepted.');
  }
}
