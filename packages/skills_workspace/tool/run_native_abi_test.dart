import 'dart:io';

import 'native_build_policy.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.absolute;
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'skills-workspace-native-abi-',
  );
  final executable = File(
    '${temporaryDirectory.path}${Platform.pathSeparator}'
    'revision_engine_abi_test${Platform.isWindows ? '.exe' : ''}',
  );
  final store = '${temporaryDirectory.path}${Platform.pathSeparator}store.git';
  final renamedStore =
      '${temporaryDirectory.path}${Platform.pathSeparator}store-released.git';

  try {
    final compiler = _compiler(options.sanitized);
    final sanitizers = options.sanitized
        ? NativeSanitizerConfiguration.parse('address,undefined')
        : NativeSanitizerConfiguration.none;
    final artifact = await _resolveArtifact(
      options: options,
      packageRoot: packageRoot,
      temporaryDirectory: temporaryDirectory,
      compiler: compiler,
      sanitizers: sanitizers,
    );
    if (!await artifact.exists()) {
      _fail('Native Asset does not exist: ${artifact.path}', 66);
    }

    final source = File(
      '${packageRoot.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}test${Platform.pathSeparator}'
      'revision_engine_abi_test.c',
    );
    final include = Directory(
      '${packageRoot.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}include',
    );
    final runtimeTest = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}'
      'runtime_lifecycle_test${Platform.isWindows ? '.exe' : ''}',
    );
    final runtimeSources = <String>[
      '${packageRoot.path}/native/test/runtime_lifecycle_test.c',
      '${packageRoot.path}/native/src/skills_workspace_runtime.c',
    ];
    final runtimeIncludes = <String>[
      '${packageRoot.path}/native/src',
      '${packageRoot.path}/native/third_party/libgit2/include',
    ];
    await _run(
      compiler,
      Platform.isWindows
          ? <String>[
              '/nologo',
              '/std:c11',
              '/W4',
              '/WX',
              '/DGIT_STATIC',
              for (final path in runtimeIncludes) '/I$path',
              ...runtimeSources,
              '/Fe:${runtimeTest.path}',
            ]
          : <String>[
              '-std=c11',
              '-Wall',
              '-Wextra',
              '-Werror',
              '-pthread',
              ...sanitizers.compilerFlags(_hostOS()),
              for (final path in runtimeIncludes) '-I$path',
              ...runtimeSources,
              '-o',
              runtimeTest.path,
            ],
      workingDirectory: temporaryDirectory.path,
      phase: 'compile runtime lifecycle harness',
    );
    await _run(
      runtimeTest.path,
      const <String>[],
      workingDirectory: temporaryDirectory.path,
      phase: 'run runtime lifecycle harness',
    );
    final compileArguments = Platform.isWindows
        ? <String>[
            '/nologo',
            '/std:c11',
            '/W4',
            '/WX',
            '/D_CRT_SECURE_NO_WARNINGS',
            if (options.sanitized) ..._unsupportedWindowsSanitizers(),
            '/I${include.path}',
            source.path,
            '/Fe:${executable.path}',
          ]
        : <String>[
            '-std=c11',
            '-Wall',
            '-Wextra',
            '-Werror',
            '-pthread',
            ...sanitizers.compilerFlags(_hostOS()),
            '-I${include.path}',
            source.path,
            '-o',
            executable.path,
            if (Platform.isLinux) '-ldl',
          ];
    await _run(
      compiler,
      compileArguments,
      workingDirectory: temporaryDirectory.path,
      phase: 'compile native ABI harness',
    );
    await _run(
      executable.path,
      <String>[artifact.absolute.path, store, renamedStore],
      workingDirectory: temporaryDirectory.path,
      phase: 'run native ABI harness',
    );
    stdout.writeln(
      options.sanitized
          ? 'sanitized native ABI test passed'
          : 'native ABI test passed',
    );
  } finally {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

Future<File> _resolveArtifact({
  required _Options options,
  required Directory packageRoot,
  required Directory temporaryDirectory,
  required String compiler,
  required NativeSanitizerConfiguration sanitizers,
}) async {
  if (options.artifact case final artifact?) {
    return artifact;
  }
  if (!options.sanitized) {
    return _defaultArtifact(packageRoot);
  }
  if (Platform.isWindows) {
    _unsupportedWindowsSanitizers();
  }

  final trackedConfiguration = NativeSanitizerConfiguration.read(
    File(
      '${packageRoot.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}sanitizers.config',
    ),
  );
  if (trackedConfiguration.isEnabled) {
    _fail(
      'Explicit sanitizer builds require native/sanitizers.config to remain '
      'none so Dart Native Assets never parses an instrumented artifact.',
      78,
    );
  }

  final policy = NativeBuildPolicy(
    packageRoot: packageRoot,
    outputDirectory: Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}explicit-native',
    ),
    targetOS: _hostOS(),
    targetArchitecture: await _hostArchitecture(),
    sanitizers: sanitizers,
  );
  return NativeLibraryBuilder(
    policy,
  ).buildExplicitDynamicLibrary(cCompiler: compiler);
}

String _compiler(bool sanitized) {
  final configured = Platform.environment['CC']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return configured;
  }
  if (Platform.isWindows) {
    return 'cl';
  }
  return sanitized ? 'clang' : 'cc';
}

NativeBuildTargetOS _hostOS() {
  if (Platform.isMacOS) {
    return NativeBuildTargetOS.macOS;
  }
  if (Platform.isLinux) {
    return NativeBuildTargetOS.linux;
  }
  if (Platform.isWindows) {
    return NativeBuildTargetOS.windows;
  }
  return _unsupportedPlatform();
}

Future<NativeBuildArchitecture> _hostArchitecture() async {
  if (Platform.isWindows) {
    final architecture = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
    if (architecture.toLowerCase() == 'amd64') {
      return NativeBuildArchitecture.x64;
    }
    throw UnsupportedError('Unsupported Windows architecture: $architecture');
  }
  final result = await Process.run('uname', const <String>['-m']);
  if (result.exitCode != 0) {
    throw StateError('Unable to determine the native host architecture.');
  }
  return switch ((result.stdout as String).trim()) {
    'arm64' || 'aarch64' => NativeBuildArchitecture.arm64,
    'x86_64' || 'amd64' => NativeBuildArchitecture.x64,
    final architecture => throw UnsupportedError(
      'Unsupported native host architecture: $architecture',
    ),
  };
}

File _defaultArtifact(Directory packageRoot) {
  final fileName = Platform.isMacOS
      ? 'libskills_workspace_native.dylib'
      : Platform.isWindows
      ? 'skills_workspace_native.dll'
      : Platform.isLinux
      ? 'libskills_workspace_native.so'
      : _unsupportedPlatform();
  return File(
    '${packageRoot.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}lib${Platform.pathSeparator}$fileName',
  );
}

List<String> _unsupportedWindowsSanitizers() =>
    throw UnsupportedError('The sanitizer ABI harness supports POSIX hosts.');

Never _unsupportedPlatform() => throw UnsupportedError(
  'The native ABI harness supports desktop hosts only.',
);

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String phase,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    _fail('$phase failed with exit code $exitCode.', exitCode);
  }
}

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}

final class _Options {
  const _Options({required this.artifact, required this.sanitized});

  final File? artifact;
  final bool sanitized;

  static _Options parse(List<String> arguments) {
    File? artifact;
    var sanitized = false;
    for (var index = 0; index < arguments.length; index += 1) {
      switch (arguments[index]) {
        case '--artifact':
          if (index + 1 >= arguments.length) _usage();
          artifact = File(arguments[++index]).absolute;
        case '--sanitized':
          sanitized = true;
        default:
          _usage();
      }
    }
    return _Options(artifact: artifact, sanitized: sanitized);
  }

  static Never _usage() => _fail(
    'usage: dart run tool/run_native_abi_test.dart '
    '[--artifact <path>] [--sanitized]',
    64,
  );
}
