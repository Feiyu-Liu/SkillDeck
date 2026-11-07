import 'dart:io';

import 'package:crypto/crypto.dart';

import 'native_artifact_inspection.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = NativeArtifactInspectionOptions.parse(arguments);
    final artifact = File(options.artifactPath).absolute;
    if (!await artifact.exists()) {
      _fail('Native artifact does not exist: ${artifact.path}', 66);
    }

    final platform = _hostPlatform();
    final expectedExports = options.kind == NativeArtifactKind.shim
        ? await _expectedShimExports()
        : const <String>{};
    final facts = switch (platform) {
      NativeArtifactPlatform.macOS => await _inspectMacOS(
        artifact,
        options.kind,
      ),
      NativeArtifactPlatform.linux => await _inspectLinux(
        artifact,
        options.kind,
      ),
      NativeArtifactPlatform.windows => await _inspectWindows(
        artifact,
        options.kind,
      ),
    };
    validateNativeArtifactFacts(
      platform: platform,
      kind: options.kind,
      artifactPath: artifact.path,
      architecture: options.architecture,
      expectedExports: expectedExports,
      expectedMinimumMacOS: options.minimumMacOS,
      facts: facts,
    );

    final digest = await sha256.bind(artifact.openRead()).first;
    final encoded = encodeNativeArtifactEvidence(
      artifactPath: artifact.path,
      platform: platform,
      kind: options.kind,
      architecture: options.architecture,
      byteSize: await artifact.length(),
      sha256: digest.toString(),
      facts: facts,
    );
    stdout.writeln(encoded);
    if (options.reportPath case final reportPath?) {
      final reportFile = File(reportPath);
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString('$encoded\n', flush: true);
    }
  } on FormatException catch (error) {
    _fail('${error.message}\n${_usage()}', 64);
  } on NativeArtifactInspectionException catch (error) {
    _fail(error.message, 1);
  }
}

NativeArtifactPlatform _hostPlatform() {
  if (Platform.isMacOS) return NativeArtifactPlatform.macOS;
  if (Platform.isLinux) return NativeArtifactPlatform.linux;
  if (Platform.isWindows) return NativeArtifactPlatform.windows;
  throw UnsupportedError('Desktop native artifact inspection only.');
}

Future<Set<String>> _expectedShimExports() async {
  final header = File(
    '${Directory.current.path}${Platform.pathSeparator}native'
    '${Platform.pathSeparator}include${Platform.pathSeparator}'
    'skills_workspace_native.h',
  );
  final contents = await header.readAsString();
  final exports = RegExp(
    r'SKILLS_WORKSPACE_EXPORT\s+int32_t\s+'
    r'(skills_workspace_[a-z0-9_]+)\s*\(',
    multiLine: true,
  ).allMatches(contents).map((match) => match.group(1)!).toSet();
  if (exports.isEmpty) {
    throw const NativeArtifactInspectionException(
      'No public shim exports were found in the native header.',
    );
  }
  return exports;
}

Future<NativeArtifactFacts> _inspectMacOS(
  File artifact,
  NativeArtifactKind kind,
) async {
  final architectures = parseLipoArchitectures(
    await _run('lipo', <String>['-archs', artifact.path]),
  );
  final installNames = parseMachOInstallNames(
    await _run('otool', <String>['-D', artifact.path]),
  );
  final dependencies = parseMachODependencies(
    await _run('otool', <String>['-L', artifact.path]),
    installNames: installNames,
  );
  final loadCommands = await _run('otool', <String>['-l', artifact.path]);
  final targets = parseMachOMinimumTargets(
    await _run('vtool', <String>['-show-build', artifact.path]),
  );
  final exports = kind == NativeArtifactKind.shim
      ? parseShimExports(
          await _run('nm', <String>['-gU', artifact.path]),
          leadingUnderscore: true,
        )
      : const <String>{};
  return NativeArtifactFacts(
    architectures: architectures,
    exports: exports,
    dynamicDependencies: dependencies,
    installNames: installNames,
    runtimeSearchPaths: parseMachORuntimeSearchPaths(loadCommands),
    resolvedDependencyPaths: const <String>[],
    minimumDeploymentTargets: targets,
  );
}

Future<NativeArtifactFacts> _inspectLinux(
  File artifact,
  NativeArtifactKind kind,
) async {
  final dynamicSection = await _run('readelf', <String>['-d', artifact.path]);
  final exports = kind == NativeArtifactKind.shim
      ? parseShimExports(
          await _run('nm', <String>['-D', '--defined-only', artifact.path]),
        )
      : const <String>{};
  return NativeArtifactFacts(
    architectures: parseLinuxArchitectures(
      await _run('readelf', <String>['-h', artifact.path]),
    ),
    exports: exports,
    dynamicDependencies: parseElfDependencies(dynamicSection),
    installNames: parseElfInstallNames(dynamicSection),
    runtimeSearchPaths: parseElfRuntimeSearchPaths(dynamicSection),
    resolvedDependencyPaths: parseLddResolvedPaths(
      await _run('ldd', <String>[artifact.path]),
    ),
    minimumDeploymentTargets: const <String>[],
  );
}

Future<NativeArtifactFacts> _inspectWindows(
  File artifact,
  NativeArtifactKind kind,
) async {
  final exports = kind == NativeArtifactKind.shim
      ? parseWindowsExports(
          await _run('dumpbin', <String>['/nologo', '/exports', artifact.path]),
        )
      : const <String>{};
  return NativeArtifactFacts(
    architectures: parseWindowsArchitectures(
      await _run('dumpbin', <String>['/nologo', '/headers', artifact.path]),
    ),
    exports: exports,
    dynamicDependencies: parseWindowsDependencies(
      await _run('dumpbin', <String>['/nologo', '/dependents', artifact.path]),
    ),
    installNames: const <String>[],
    runtimeSearchPaths: const <String>[],
    resolvedDependencyPaths: const <String>[],
    minimumDeploymentTargets: const <String>[],
  );
}

Future<String> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    final diagnostic = (result.stderr as String).trim();
    throw NativeArtifactInspectionException(
      '$executable failed with exit code ${result.exitCode}'
      '${diagnostic.isEmpty ? '.' : ': $diagnostic'}',
    );
  }
  return result.stdout as String;
}

String _usage() =>
    'usage: dart run tool/inspect_native_artifact.dart '
    '--artifact <path> --architecture <arm64|x64|universal> '
    '[--kind <shim|sqlite>] [--macos-min <version[,version]>] '
    '[--report <path>]';

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}
