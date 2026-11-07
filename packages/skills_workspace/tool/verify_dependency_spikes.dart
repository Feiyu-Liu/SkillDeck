import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'native_build_policy.dart';

Future<void> main(List<String> arguments) async {
  final reportPath = _reportPath(arguments);
  final pubspec =
      loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
  final lock = loadYaml(await File('pubspec.lock').readAsString()) as YamlMap;
  final dependencies = pubspec['dependencies'] as YamlMap;
  final devDependencies = pubspec['dev_dependencies'] as YamlMap;
  final lockedPackages = lock['packages'] as YamlMap;

  const selected = <String, String>{
    'archive': '4.1.0',
    'canonical_json': '1.1.3',
    'code_assets': '1.2.1',
    'drift': '2.34.3',
    'drift_dev': '2.34.5',
    'ffi': '2.2.0',
    'ffigen': '21.0.0',
    'crypto': '3.0.7',
    'hooks': '2.0.2',
    'http': '1.6.0',
    'logging': '1.3.0',
    'native_toolchain_c': '0.19.1',
    'path': '1.9.1',
    'posix': '6.5.2',
    'sqlite3': '3.5.2',
    'unorm_dart': '0.3.2',
    'uuid': '4.6.0',
    'win32': '6.4.0',
    'yaml': '3.1.3',
  };
  for (final entry in selected.entries) {
    final isDeclared =
        dependencies.containsKey(entry.key) ||
        devDependencies.containsKey(entry.key);
    if (!isDeclared) _fail('Selected dependency is not direct: ${entry.key}.');
    final record = lockedPackages[entry.key] as YamlMap?;
    if (record?['version'] != entry.value) {
      _fail(
        'Selected dependency ${entry.key} resolved to ${record?['version']}; '
        'expected ${entry.value}.',
      );
    }
    final dependencyKind = record?['dependency'] as String?;
    if (dependencyKind == null || !dependencyKind.startsWith('direct ')) {
      _fail('Selected dependency is not direct in the lockfile: ${entry.key}.');
    }
  }

  const absentCandidates = <String>{
    'file_lock',
    'git',
    'git2dart',
    'ligit',
    'native_toolchain_cmake',
    'retry',
  };
  for (final package in absentCandidates) {
    if (dependencies.containsKey(package) ||
        devDependencies.containsKey(package) ||
        lockedPackages.containsKey(package)) {
      _fail('Rejected dependency is present: $package.');
    }
  }
  for (final package in const <String>['pool', 'process', 'watcher']) {
    if (dependencies.containsKey(package) ||
        devDependencies.containsKey(package)) {
      _fail('Deferred/reference dependency became direct: $package.');
    }
  }

  final lockRecord =
      jsonDecode(await File('native/libgit2.lock.json').readAsString())
          as Map<String, Object?>;
  if (lockRecord['version'] != '1.9.7' ||
      lockRecord['tag'] != 'v1.9.7' ||
      lockRecord['commit'] != '49e408b3208bc3093757a1c2db938d3590f3f412' ||
      lockRecord['archiveSha256'] !=
          '173c45822177d73bb1a97555d864ad04a3e0486eb0bc3455443a4669a35d8aa2') {
    _fail('Vendored libgit2 identity does not match the accepted pin.');
  }
  final build = (lockRecord['build'] as Map).cast<String, Object?>();
  const requiredBuildValues = <String, String>{
    'BUILD_SHARED_LIBS': 'OFF',
    'BUILD_TESTS': 'OFF',
    'BUILD_CLI': 'OFF',
    'USE_THREADS': 'ON',
    'USE_SSH': 'OFF',
    'USE_GSSAPI': 'OFF',
    'USE_NTLMCLIENT': 'OFF',
    'USE_BUNDLED_ZLIB': 'ON',
    'USE_HTTP_PARSER': 'builtin',
    'REGEX_BACKEND': 'builtin',
    'USE_ICONV': 'OFF',
    'USE_SHA1': 'CollisionDetection',
    'USE_SHA256': 'Builtin',
  };
  for (final entry in requiredBuildValues.entries) {
    if (build[entry.key] != entry.value) {
      _fail('libgit2 build switch ${entry.key} is not ${entry.value}.');
    }
  }
  // The lock file records the build the hook performs. Cross-check it
  // against the policy so the two cannot drift apart silently.
  final httpsBackends = (build['USE_HTTPS'] as Map?)?.cast<String, Object?>();
  const lockPlatformKeys = <NativeBuildTargetOS, String>{
    NativeBuildTargetOS.macOS: 'macos',
    NativeBuildTargetOS.linux: 'linux',
    NativeBuildTargetOS.windows: 'windows',
  };
  if (httpsBackends == null ||
      httpsBackends.length != lockPlatformKeys.length) {
    _fail('libgit2 build switch USE_HTTPS must name one backend per platform.');
  }
  for (final MapEntry(key: targetOS, value: lockKey)
      in lockPlatformKeys.entries) {
    final policy = NativeBuildPolicy(
      packageRoot: Directory.current,
      outputDirectory: Directory.systemTemp,
      targetOS: targetOS,
      targetArchitecture: NativeBuildArchitecture.x64,
      sanitizers: NativeSanitizerConfiguration.none,
    );
    if (httpsBackends[lockKey] != policy.httpsBackend) {
      _fail(
        'libgit2 lock USE_HTTPS for $lockKey is ${httpsBackends[lockKey]}; '
        'the build policy uses ${policy.httpsBackend}.',
      );
    }
    final configure = policy.libgit2ConfigureArguments().toSet();
    for (final entry in <String, String>{
      ...requiredBuildValues,
      'USE_HTTPS': policy.httpsBackend,
    }.entries) {
      if (!configure.contains('-D${entry.key}=${entry.value}')) {
        _fail(
          'The $lockKey build policy does not configure '
          '${entry.key}=${entry.value}.',
        );
      }
    }
  }

  final versionHeader = await File(
    'native/third_party/libgit2/include/git2/version.h',
  ).readAsString();
  for (final expectation in const <(String, int)>[
    ('LIBGIT2_VERSION_MAJOR', 1),
    ('LIBGIT2_VERSION_MINOR', 9),
    ('LIBGIT2_VERSION_REVISION', 7),
  ]) {
    if (!RegExp(
      '^#define\\s+${expectation.$1}\\s+${expectation.$2}\\s*\$',
      multiLine: true,
    ).hasMatch(versionHeader)) {
      _fail('Vendored source header does not prove libgit2 1.9.7.');
    }
  }

  final commonHeader = await File(
    'native/third_party/libgit2/include/git2/common.h',
  ).readAsString();
  if (!RegExp(
    r'#if defined\(GIT_STATIC\)\s*# define GIT_EXTERN\(type\) extern type',
    multiLine: true,
  ).hasMatch(commonHeader)) {
    _fail('The vendored static-libgit2 export patch is missing.');
  }

  final expectedExports =
      RegExp(
            r'SKILLS_WORKSPACE_EXPORT\s+int32_t\s+'
            r'(skills_workspace_[a-z0-9_]+)\s*\(',
            multiLine: true,
          )
          .allMatches(
            await File(
              'native/include/skills_workspace_native.h',
            ).readAsString(),
          )
          .map((match) => match.group(1)!)
          .toSet();
  final macOSExports =
      (await File('native/exports/macos.exports').readAsLines())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => line.startsWith('_') ? line.substring(1) : line)
          .toSet();
  final linuxExports =
      RegExp(r'^\s*(skills_workspace_[a-z0-9_]+);\s*$', multiLine: true)
          .allMatches(await File('native/exports/linux.map').readAsString())
          .map((match) => match.group(1)!)
          .toSet();
  if (!_sameSet(expectedExports, macOSExports) ||
      !_sameSet(expectedExports, linuxExports)) {
    _fail('Native export controls do not match the declared C ABI.');
  }

  for (final file in const <String>[
    'native/THIRD_PARTY_NOTICES.md',
    'native/third_party/libgit2/COPYING',
  ]) {
    if (!await File(file).exists()) {
      _fail('Required license notice is missing: $file.');
    }
  }
  if ((await File('native/sanitizers.config').readAsString()).trim() !=
      'none') {
    _fail('The committed native sanitizer mode must be none.');
  }

  final report = <String, Object>{
    'schemaVersion': 1,
    'selected': selected,
    'rejected': <String>['file_lock', 'git', 'git2dart', 'ligit', 'retry'],
    'deferredOrTransitiveOnly': <String>[
      'native_toolchain_cmake@0.3.1',
      'pool',
      'process',
      'watcher@1.2.1',
    ],
    'libgit2': <String, Object?>{
      'version': lockRecord['version'],
      'commit': lockRecord['commit'],
      'archiveSha256': lockRecord['archiveSha256'],
      'declaredExportCount': expectedExports.length,
    },
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln(encoded);
  if (reportPath case final path?) {
    final output = File(path);
    await output.parent.create(recursive: true);
    await output.writeAsString('$encoded\n', flush: true);
  }
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String? _reportPath(List<String> arguments) {
  if (arguments.isEmpty) return null;
  if (arguments.length == 2 && arguments.first == '--report') {
    return arguments.last;
  }
  stderr.writeln(
    'usage: dart run tool/verify_dependency_spikes.dart [--report <path>]',
  );
  exit(64);
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
