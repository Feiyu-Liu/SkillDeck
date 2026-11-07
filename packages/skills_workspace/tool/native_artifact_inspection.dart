import 'dart:convert';

enum NativeArtifactKind { shim, sqlite }

enum NativeArtifactPlatform { macOS, linux, windows }

final class NativeArtifactInspectionException implements Exception {
  const NativeArtifactInspectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NativeArtifactInspectionOptions {
  const NativeArtifactInspectionOptions({
    required this.artifactPath,
    required this.architecture,
    required this.kind,
    this.minimumMacOS = const <String>{},
    this.reportPath,
  });

  final String artifactPath;
  final String architecture;
  final NativeArtifactKind kind;
  final Set<String> minimumMacOS;
  final String? reportPath;

  static NativeArtifactInspectionOptions parse(List<String> arguments) {
    String? artifact;
    String? architecture;
    var kind = NativeArtifactKind.shim;
    var minimumMacOS = const <String>{};
    String? report;
    for (var index = 0; index < arguments.length; index += 1) {
      final name = arguments[index];
      if (index + 1 >= arguments.length) {
        throw const FormatException('An option value is missing.');
      }
      final value = arguments[++index];
      switch (name) {
        case '--artifact':
          artifact = value;
        case '--architecture':
          architecture = value;
        case '--kind':
          kind = switch (value) {
            'shim' => NativeArtifactKind.shim,
            'sqlite' => NativeArtifactKind.sqlite,
            _ => throw FormatException('Unsupported artifact kind: $value.'),
          };
        case '--macos-min':
          minimumMacOS = value
              .split(',')
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toSet();
          if (minimumMacOS.isEmpty) {
            throw const FormatException('--macos-min must not be empty.');
          }
        case '--report':
          report = value;
        default:
          throw FormatException('Unsupported option: $name.');
      }
    }
    if (artifact == null || artifact.isEmpty) {
      throw const FormatException('--artifact is required.');
    }
    if (architecture == null ||
        !const <String>{'arm64', 'x64', 'universal'}.contains(architecture)) {
      throw const FormatException(
        '--architecture must be arm64, x64, or universal.',
      );
    }
    return NativeArtifactInspectionOptions(
      artifactPath: artifact,
      architecture: architecture,
      kind: kind,
      minimumMacOS: minimumMacOS,
      reportPath: report,
    );
  }
}

final class NativeArtifactFacts {
  NativeArtifactFacts({
    required Set<String> architectures,
    required Set<String> exports,
    required Iterable<String> dynamicDependencies,
    required Iterable<String> installNames,
    required Iterable<String> runtimeSearchPaths,
    required Iterable<String> resolvedDependencyPaths,
    required Iterable<String> minimumDeploymentTargets,
  }) : architectures = Set<String>.unmodifiable(architectures),
       exports = Set<String>.unmodifiable(exports),
       dynamicDependencies = _sorted(dynamicDependencies),
       installNames = _sorted(installNames),
       runtimeSearchPaths = _sorted(runtimeSearchPaths),
       resolvedDependencyPaths = _sorted(resolvedDependencyPaths),
       minimumDeploymentTargets = _sorted(minimumDeploymentTargets);

  final Set<String> architectures;
  final Set<String> exports;
  final List<String> dynamicDependencies;
  final List<String> installNames;
  final List<String> runtimeSearchPaths;
  final List<String> resolvedDependencyPaths;
  final List<String> minimumDeploymentTargets;

  Map<String, Object> toJson() => <String, Object>{
    'architectures': architectures.toList()..sort(),
    'exports': exports.toList()..sort(),
    'dynamicDependencies': dynamicDependencies,
    'installNames': installNames,
    'runtimeSearchPaths': runtimeSearchPaths,
    'resolvedDependencyPaths': resolvedDependencyPaths,
    'minimumDeploymentTargets': minimumDeploymentTargets,
  };

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}

Set<String> expectedArchitectures(
  NativeArtifactPlatform platform,
  String architecture,
) => switch ((platform, architecture)) {
  (NativeArtifactPlatform.macOS, 'arm64') => const <String>{'arm64'},
  (NativeArtifactPlatform.macOS, 'x64') => const <String>{'x86_64'},
  (NativeArtifactPlatform.macOS, 'universal') => const <String>{
    'arm64',
    'x86_64',
  },
  (NativeArtifactPlatform.linux, 'x64') ||
  (NativeArtifactPlatform.windows, 'x64') => const <String>{'x86_64'},
  _ => throw NativeArtifactInspectionException(
    'Unsupported architecture $architecture for ${platform.name}.',
  ),
};

Set<String> parseLipoArchitectures(String output) => output
    .trim()
    .split(RegExp(r'\s+'))
    .where((value) => value.isNotEmpty)
    .toSet();

Set<String> parseMachOInstallNames(String output) {
  final result = <String>{};
  for (final line in const LineSplitter().convert(output)) {
    final value = line.trim();
    if (value.isEmpty || value.contains('(architecture ')) continue;
    if (value.startsWith('@') || value.startsWith('/')) result.add(value);
  }
  return result;
}

List<String> parseMachODependencies(
  String output, {
  required Set<String> installNames,
}) {
  final result = <String>{};
  for (final line in const LineSplitter().convert(output)) {
    if (!line.startsWith('\t')) continue;
    final value = line.trim().split(RegExp(r'\s+')).first;
    if (!installNames.contains(value)) result.add(value);
  }
  return result.toList()..sort();
}

Set<String> parseMachORuntimeSearchPaths(String output) {
  final result = <String>{};
  var expectsPath = false;
  for (final line in const LineSplitter().convert(output)) {
    final value = line.trim();
    if (value == 'cmd LC_RPATH') {
      expectsPath = true;
      continue;
    }
    if (!expectsPath) continue;
    final match = RegExp(
      r'^path\s+(.+?)\s+\(offset\s+\d+\)$',
    ).firstMatch(value);
    if (match != null) {
      result.add(match.group(1)!);
      expectsPath = false;
    } else if (value.startsWith('cmd ') && value != 'cmd LC_RPATH') {
      expectsPath = false;
    }
  }
  return result;
}

Set<String> parseMachOMinimumTargets(String output) => RegExp(
  r'^\s*minos\s+([0-9.]+)\s*$',
  multiLine: true,
).allMatches(output).map((match) => match.group(1)!).toSet();

Set<String> parseLinuxArchitectures(String output) {
  if (RegExp(
    r'Machine:\s+(?:Advanced Micro Devices X86-64|AMD x86-64)',
  ).hasMatch(output)) {
    return const <String>{'x86_64'};
  }
  return const <String>{};
}

List<String> parseElfDependencies(String output) => RegExp(
  r'\(NEEDED\).*?\[([^\]]+)\]',
).allMatches(output).map((match) => match.group(1)!).toSet().toList()..sort();

Set<String> parseElfInstallNames(String output) => RegExp(
  r'\(SONAME\).*?\[([^\]]+)\]',
).allMatches(output).map((match) => match.group(1)!).toSet();

Set<String> parseElfRuntimeSearchPaths(String output) {
  final result = <String>{};
  for (final match in RegExp(
    r'\((?:RPATH|RUNPATH)\).*?\[([^\]]*)\]',
  ).allMatches(output)) {
    result.addAll(
      match
          .group(1)!
          .split(':')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    );
  }
  return result;
}

Set<String> parseLddResolvedPaths(String output) {
  final result = <String>{};
  for (final line in const LineSplitter().convert(output)) {
    final arrow = RegExp(r'=>\s+(/\S+)').firstMatch(line);
    if (arrow != null) {
      result.add(arrow.group(1)!);
      continue;
    }
    final direct = RegExp(r'^\s*(/\S+)').firstMatch(line);
    if (direct != null) result.add(direct.group(1)!);
  }
  return result;
}

Set<String> parseWindowsArchitectures(String output) {
  if (RegExp(
    r'(?:8664\s+machine\s+\(x64\)|machine\s*\(x64\))',
    caseSensitive: false,
  ).hasMatch(output)) {
    return const <String>{'x86_64'};
  }
  return const <String>{};
}

List<String> parseWindowsDependencies(String output) => RegExp(
  r'^\s+([A-Za-z0-9_.-]+\.dll)\s*$',
  caseSensitive: false,
  multiLine: true,
).allMatches(output).map((match) => match.group(1)!).toSet().toList()..sort();

Set<String> parseShimExports(String output, {bool leadingUnderscore = false}) {
  final exports = <String>{};
  for (final line in const LineSplitter().convert(output)) {
    final match = RegExp(
      r'^[ \t]*[0-9A-Fa-f]+[ \t]+([A-Za-z?])[ \t]+(\S+)[ \t]*$',
    ).firstMatch(line);
    if (match == null) continue;
    final symbolType = match.group(1)!;
    // GNU nm reports an ELF version-definition node as an absolute symbol
    // (for example `A SKILLS_WORKSPACE_1.0`). It is metadata for versioned
    // dynamic symbols, not an addressable export in the package ABI.
    if (symbolType == 'A' || symbolType == 'a') continue;
    final rawName = match.group(2)!;
    if (leadingUnderscore) {
      if (!rawName.startsWith('_')) continue;
      exports.add(rawName.substring(1));
    } else {
      final versionSeparator = rawName.indexOf('@');
      exports.add(
        versionSeparator == -1
            ? rawName
            : rawName.substring(0, versionSeparator),
      );
    }
  }
  return exports;
}

Set<String> parseWindowsExports(String output) {
  final exports = <String>{};
  final row = RegExp(
    r'^[ \t]*(\d+)[ \t]+([0-9A-Fa-f]+)[ \t]+'
    r'([0-9A-Fa-f]+)[ \t]+(\S+)(?:[ \t]+.*)?$',
    multiLine: true,
  );
  for (final match in row.allMatches(output)) {
    final ordinal = match.group(1)!;
    final name = match.group(4)!;
    exports.add(name == '[NONAME]' ? '#ordinal:$ordinal' : name);
  }
  return exports;
}

void validateNativeArtifactFacts({
  required NativeArtifactPlatform platform,
  required NativeArtifactKind kind,
  required String artifactPath,
  required String architecture,
  required Set<String> expectedExports,
  required Set<String> expectedMinimumMacOS,
  required NativeArtifactFacts facts,
}) {
  final expected = expectedArchitectures(platform, architecture);
  if (facts.architectures.length != expected.length ||
      !facts.architectures.containsAll(expected)) {
    throw NativeArtifactInspectionException(
      'Artifact architectures ${facts.architectures} do not equal $expected.',
    );
  }
  _validateArtifactName(platform, kind, artifactPath);
  _validateInstallNames(platform, kind, facts.installNames);
  _validateDependencies(platform, kind, facts.dynamicDependencies);
  final allowedRuntimeSearchPaths = switch (platform) {
    NativeArtifactPlatform.linux => const <String>{r'$ORIGIN'},
    NativeArtifactPlatform.macOS ||
    NativeArtifactPlatform.windows => const <String>{},
  };
  final disallowedRuntimeSearchPaths = facts.runtimeSearchPaths
      .where((path) => !allowedRuntimeSearchPaths.contains(path))
      .toList();
  if (disallowedRuntimeSearchPaths.isNotEmpty) {
    throw NativeArtifactInspectionException(
      'Artifact has disallowed runtime search paths: '
      '$disallowedRuntimeSearchPaths.',
    );
  }
  _validateResolvedDependencyPaths(platform, facts.resolvedDependencyPaths);
  if (kind == NativeArtifactKind.shim) {
    if (facts.exports.length != expectedExports.length ||
        !facts.exports.containsAll(expectedExports)) {
      final missing = expectedExports.difference(facts.exports).toList()
        ..sort();
      final unexpected = facts.exports.difference(expectedExports).toList()
        ..sort();
      throw NativeArtifactInspectionException(
        'Native export mismatch; missing=$missing unexpected=$unexpected.',
      );
    }
  } else if (expectedExports.isNotEmpty) {
    throw const NativeArtifactInspectionException(
      'SQLite inspection must not receive a shim export allowlist.',
    );
  }
  if (platform == NativeArtifactPlatform.macOS &&
      expectedMinimumMacOS.isNotEmpty &&
      (facts.minimumDeploymentTargets.length != expectedMinimumMacOS.length ||
          !facts.minimumDeploymentTargets.toSet().containsAll(
            expectedMinimumMacOS,
          ))) {
    throw NativeArtifactInspectionException(
      'Mach-O minimum targets ${facts.minimumDeploymentTargets} do not equal '
      '$expectedMinimumMacOS.',
    );
  }
}

void _validateResolvedDependencyPaths(
  NativeArtifactPlatform platform,
  List<String> paths,
) {
  if (platform != NativeArtifactPlatform.linux) {
    if (paths.isNotEmpty) {
      throw NativeArtifactInspectionException(
        '${platform.name} inspection reported unexpected resolved paths: $paths.',
      );
    }
    return;
  }
  final violations = paths.where((value) {
    final lower = value.toLowerCase();
    if (lower.contains('git2') || lower.contains('sqlite3')) return true;
    return !value.startsWith('/lib/') &&
        !value.startsWith('/lib64/') &&
        !value.startsWith('/usr/lib/');
  }).toList();
  if (violations.isNotEmpty) {
    throw NativeArtifactInspectionException(
      'ELF dependencies resolved outside system library roots: $violations.',
    );
  }
}

void _validateArtifactName(
  NativeArtifactPlatform platform,
  NativeArtifactKind kind,
  String artifactPath,
) {
  final normalized = artifactPath.replaceAll('\\', '/');
  final name = normalized.split('/').last.toLowerCase();
  final allowed = switch ((platform, kind)) {
    (NativeArtifactPlatform.macOS, NativeArtifactKind.shim) => const <String>{
      'skills_workspace_native',
      'libskills_workspace_native.dylib',
    },
    (NativeArtifactPlatform.macOS, NativeArtifactKind.sqlite) => const <String>{
      'sqlite3',
      'libsqlite3.dylib',
    },
    (NativeArtifactPlatform.linux, NativeArtifactKind.shim) => const <String>{
      'libskills_workspace_native.so',
    },
    (NativeArtifactPlatform.linux, NativeArtifactKind.sqlite) => const <String>{
      'libsqlite3.so',
    },
    (NativeArtifactPlatform.windows, NativeArtifactKind.shim) => const <String>{
      'skills_workspace_native.dll',
    },
    (NativeArtifactPlatform.windows, NativeArtifactKind.sqlite) =>
      const <String>{'sqlite3.dll'},
  };
  if (!allowed.contains(name)) {
    throw NativeArtifactInspectionException(
      'Unexpected ${kind.name} artifact name: $name.',
    );
  }
}

void _validateInstallNames(
  NativeArtifactPlatform platform,
  NativeArtifactKind kind,
  List<String> installNames,
) {
  final expected = switch ((platform, kind)) {
    (NativeArtifactPlatform.macOS, NativeArtifactKind.shim) => const <String>{
      '@rpath/skills_workspace_native.framework/skills_workspace_native',
      '@rpath/libskills_workspace_native.dylib',
    },
    (NativeArtifactPlatform.macOS, NativeArtifactKind.sqlite) => const <String>{
      '@rpath/sqlite3.framework/sqlite3',
      '@rpath/libsqlite3.dylib',
    },
    (NativeArtifactPlatform.linux, NativeArtifactKind.shim) => const <String>{
      'libskills_workspace_native.so',
    },
    (NativeArtifactPlatform.linux, NativeArtifactKind.sqlite) => const <String>{
      'libsqlite3.so',
    },
    (NativeArtifactPlatform.windows, _) => const <String>{},
  };
  if (platform == NativeArtifactPlatform.windows) {
    if (installNames.isNotEmpty) {
      throw NativeArtifactInspectionException(
        'PE artifacts must not report install names: $installNames.',
      );
    }
    return;
  }
  if (platform == NativeArtifactPlatform.linux &&
      kind == NativeArtifactKind.sqlite &&
      installNames.isEmpty) {
    return;
  }
  if (installNames.length != 1 || !expected.contains(installNames.single)) {
    throw NativeArtifactInspectionException(
      'Artifact install names $installNames are not in $expected.',
    );
  }
}

void _validateDependencies(
  NativeArtifactPlatform platform,
  NativeArtifactKind kind,
  List<String> dependencies,
) {
  final violations = <String>[];
  for (final dependency in dependencies) {
    if (_isExternalVersionStoreDependency(dependency) ||
        !_isAllowedSystemDependency(platform, kind, dependency)) {
      violations.add(dependency);
    }
  }
  if (violations.isNotEmpty) {
    throw NativeArtifactInspectionException(
      'Artifact has dependencies outside the ${platform.name}/${kind.name} '
      'system allowlist: $violations.',
    );
  }
}

/// Link-time dependencies that would bypass the pinned, statically linked
/// stack. Linux loads the distribution's OpenSSL at run time instead of
/// linking it, so `libssl` and `libcrypto` must never appear here.
bool _isExternalVersionStoreDependency(String dependency) {
  final lower = dependency.toLowerCase();
  return lower.contains('git2') ||
      lower.contains('libssh') ||
      lower.contains('libssl') ||
      lower.contains('libcrypto') ||
      lower.contains('libcurl') ||
      lower.contains('sqlite3');
}

bool _isAllowedSystemDependency(
  NativeArtifactPlatform platform,
  NativeArtifactKind kind,
  String dependency,
) {
  switch (platform) {
    case NativeArtifactPlatform.macOS:
      if (!dependency.startsWith('/usr/lib/') &&
          !dependency.startsWith('/System/Library/Frameworks/')) {
        return false;
      }
      final allowed = switch (kind) {
        // Security and CoreFoundation serve libgit2's SecureTransport HTTPS
        // backend (ADR-0106).
        NativeArtifactKind.shim => const <String>{
          '/usr/lib/libSystem.B.dylib',
          '/System/Library/Frameworks/Security.framework/Versions/A/Security',
          '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/'
              'CoreFoundation',
        },
        NativeArtifactKind.sqlite => const <String>{
          '/usr/lib/libSystem.B.dylib',
        },
      };
      return allowed.contains(dependency);
    case NativeArtifactPlatform.linux:
      if (dependency.contains('/') || dependency.contains('\\')) return false;
      final allowed = switch (kind) {
        NativeArtifactKind.shim => const <String>{
          'libc.so.6',
          'libm.so.6',
          'libdl.so.2',
          'libpthread.so.0',
          'librt.so.1',
          'libgcc_s.so.1',
        },
        NativeArtifactKind.sqlite => const <String>{
          'libc.so.6',
          'libm.so.6',
          'libdl.so.2',
          'libpthread.so.0',
          'librt.so.1',
        },
      };
      return allowed.contains(dependency);
    case NativeArtifactPlatform.windows:
      if (dependency.contains('/') ||
          dependency.contains('\\') ||
          dependency.contains(':')) {
        return false;
      }
      final upper = dependency.toUpperCase();
      final allowed = switch (kind) {
        NativeArtifactKind.shim => const <String>{
          'KERNEL32.DLL',
          'ADVAPI32.DLL',
          'BCRYPT.DLL',
          'OLE32.DLL',
          'SHELL32.DLL',
          'USER32.DLL',
          'WS2_32.DLL',
          'SECUR32.DLL',
          // WinHTTP and its certificate and RPC helpers serve libgit2's
          // WinHTTP HTTPS backend (ADR-0106).
          'WINHTTP.DLL',
          'CRYPT32.DLL',
          'RPCRT4.DLL',
          'VCRUNTIME140.DLL',
          'VCRUNTIME140_1.DLL',
          'MSVCP140.DLL',
          'UCRTBASE.DLL',
        },
        NativeArtifactKind.sqlite => const <String>{
          'KERNEL32.DLL',
          'ADVAPI32.DLL',
          'BCRYPT.DLL',
          'VCRUNTIME140.DLL',
          'VCRUNTIME140_1.DLL',
          'MSVCP140.DLL',
          'UCRTBASE.DLL',
        },
      };
      return allowed.contains(upper) ||
          RegExp(r'^(?:API|EXT)-MS-WIN-[A-Z0-9_.-]+\.DLL$').hasMatch(upper);
  }
}

String encodeNativeArtifactEvidence({
  required String artifactPath,
  required NativeArtifactPlatform platform,
  required NativeArtifactKind kind,
  required String architecture,
  required int byteSize,
  required String sha256,
  required NativeArtifactFacts facts,
}) => const JsonEncoder.withIndent('  ').convert(<String, Object>{
  'schemaVersion': 2,
  'artifact': artifactPath,
  'artifactKind': kind.name,
  'platform': platform.name,
  'requestedArchitecture': architecture,
  'byteSize': byteSize,
  'sha256': sha256,
  ...facts.toJson(),
});
