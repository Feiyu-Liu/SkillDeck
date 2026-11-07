import 'dart:convert';
import 'dart:io';

enum NativeBuildTargetOS { macOS, linux, windows }

enum NativeBuildArchitecture { arm64, x64 }

final class NativeSanitizerConfiguration {
  const NativeSanitizerConfiguration._(this.names);

  static const none = NativeSanitizerConfiguration._(<String>[]);

  static NativeSanitizerConfiguration parse(String requested) {
    final trimmed = requested.trim();
    if (trimmed == 'none') {
      return none;
    }
    final normalized = trimmed
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    const supported = <String>{'address', 'undefined'};
    if (normalized.isEmpty || !supported.containsAll(normalized)) {
      throw ArgumentError.value(
        requested,
        'sanitizers',
        'must be none or contain only address and/or undefined',
      );
    }
    return NativeSanitizerConfiguration._(<String>[
      if (normalized.contains('address')) 'address',
      if (normalized.contains('undefined')) 'undefined',
    ]);
  }

  static NativeSanitizerConfiguration read(File configuration) {
    if (!configuration.existsSync()) {
      throw StateError('The native sanitizer configuration is missing.');
    }
    return parse(configuration.readAsStringSync());
  }

  final List<String> names;

  bool get isEnabled => names.isNotEmpty;

  String get serialized => isEnabled ? names.join(',') : 'none';

  List<String> compilerFlags(NativeBuildTargetOS targetOS) {
    if (!isEnabled) {
      return const <String>[];
    }
    if (targetOS != NativeBuildTargetOS.macOS &&
        targetOS != NativeBuildTargetOS.linux) {
      throw UnsupportedError(
        'Native sanitizers are supported only on macOS and Linux.',
      );
    }
    return <String>['-fsanitize=${names.join(',')}', '-fno-omit-frame-pointer'];
  }
}

final class NativeBuildPolicy {
  const NativeBuildPolicy({
    required this.packageRoot,
    required this.outputDirectory,
    required this.targetOS,
    required this.targetArchitecture,
    required this.sanitizers,
  });

  final Directory packageRoot;
  final Directory outputDirectory;
  final NativeBuildTargetOS targetOS;
  final NativeBuildArchitecture targetArchitecture;
  final NativeSanitizerConfiguration sanitizers;

  Directory get libgit2SourceDirectory =>
      Directory(_path('native', 'third_party', 'libgit2'));

  Directory get libgit2BuildDirectory =>
      Directory(_outputPath('libgit2-build'));

  Directory get nativeIncludeDirectory => Directory(_path('native', 'include'));

  Directory get libgit2IncludeDirectory =>
      Directory(_path('native', 'third_party', 'libgit2', 'include'));

  List<File> get shimSources => <File>[
    File(_path('native', 'src', 'native_ping.c')),
    File(_path('native', 'src', 'revision_engine.c')),
    File(_path('native', 'src', 'skills_workspace_runtime.c')),
    File(_path('native', 'src', 'source_transport.c')),
  ];

  File get dynamicLibrary => File(
    _outputPath(switch (targetOS) {
      NativeBuildTargetOS.macOS => 'libskills_workspace_native.dylib',
      NativeBuildTargetOS.linux => 'libskills_workspace_native.so',
      NativeBuildTargetOS.windows => 'skills_workspace_native.dll',
    }),
  );

  List<String> get sanitizerCompilerFlags => sanitizers.compilerFlags(targetOS);

  /// The platform TLS backend that serves libgit2's HTTPS transport.
  ///
  /// Each backend uses the operating system's trust store: SecureTransport on
  /// macOS, WinHTTP on Windows, and the distribution's OpenSSL loaded at run
  /// time on Linux, so no CA bundle path is compiled into the artifact.
  String get httpsBackend => switch (targetOS) {
    NativeBuildTargetOS.macOS => 'SecureTransport',
    NativeBuildTargetOS.linux => 'OpenSSL-Dynamic',
    NativeBuildTargetOS.windows => 'WinHTTP',
  };

  /// System frameworks the macOS shim links for the HTTPS backend.
  List<String> get shimFrameworks => switch (targetOS) {
    NativeBuildTargetOS.macOS => const <String>['Security', 'CoreFoundation'],
    _ => const <String>[],
  };

  /// System libraries the shim links besides the pinned libgit2 archive.
  List<String> get shimSystemLibraries => switch (targetOS) {
    NativeBuildTargetOS.macOS => const <String>[],
    NativeBuildTargetOS.linux => const <String>['dl'],
    NativeBuildTargetOS.windows => const <String>[
      'ws2_32.lib',
      'secur32.lib',
      'advapi32.lib',
      'winhttp.lib',
      'rpcrt4.lib',
      'crypt32.lib',
      'ole32.lib',
    ],
  };

  /// Feature defines the pinned libgit2 configuration must produce.
  List<String> get requiredLibgit2Features => <String>[
    ..._requiredLibgit2Features,
    'GIT_HTTPS',
    ...switch (targetOS) {
      NativeBuildTargetOS.macOS => const <String>['GIT_SECURE_TRANSPORT'],
      NativeBuildTargetOS.linux => const <String>[
        'GIT_OPENSSL',
        'GIT_OPENSSL_DYNAMIC',
      ],
      NativeBuildTargetOS.windows => const <String>['GIT_WINHTTP'],
    },
  ];

  /// Feature defines the pinned libgit2 configuration must not produce.
  List<String> get forbiddenLibgit2Features => <String>[
    for (final feature in _forbiddenLibgit2Features)
      if (!requiredLibgit2Features.contains(feature)) feature,
  ];

  List<String> get shimFlags => <String>[
    if (targetOS != NativeBuildTargetOS.windows) '-fvisibility=hidden',
    if (targetOS == NativeBuildTargetOS.linux) '-D_GNU_SOURCE',
    ...sanitizerCompilerFlags,
    if (targetOS == NativeBuildTargetOS.macOS)
      '-mmacos-version-min=$macOSDeploymentTarget',
    ...exportControlFlags,
    for (final framework in shimFrameworks) '-Wl,-framework,$framework',
  ];

  List<String> get exportControlFlags => switch (targetOS) {
    NativeBuildTargetOS.macOS => <String>[
      '-Wl,-exported_symbols_list,${_path('native', 'exports', 'macos.exports')}',
      '-Wl,-S',
      '-Wl,-x',
    ],
    NativeBuildTargetOS.linux => <String>[
      '-Wl,--version-script=${_path('native', 'exports', 'linux.map')}',
      '-Wl,-soname,libskills_workspace_native.so',
      '-Wl,-s',
    ],
    NativeBuildTargetOS.windows => const <String>[],
  };

  String get macOSDeploymentTarget {
    if (targetOS != NativeBuildTargetOS.macOS) {
      throw StateError(
        'A macOS deployment target was requested for $targetOS.',
      );
    }
    return targetArchitecture == NativeBuildArchitecture.arm64
        ? '11.0'
        : '10.15';
  }

  String get cmakeArchitecture => switch (targetArchitecture) {
    NativeBuildArchitecture.arm64 => 'arm64',
    NativeBuildArchitecture.x64 => 'x86_64',
  };

  List<String> libgit2ConfigureArguments({
    String? cCompiler,
    String? generator,
    String? makeProgram,
  }) {
    final cFlags = <String>[
      if (targetOS == NativeBuildTargetOS.windows) '/DGIT_STATIC',
      if (targetOS == NativeBuildTargetOS.windows)
        '/DSHA1DC_FORCE_ALIGNED_ACCESS'
      else
        '-DSHA1DC_FORCE_ALIGNED_ACCESS',
      ...sanitizerCompilerFlags,
    ];
    return <String>[
      if (generator != null) ...<String>['-G', generator],
      '-S',
      libgit2SourceDirectory.path,
      '-B',
      libgit2BuildDirectory.path,
      if (makeProgram != null) '-DCMAKE_MAKE_PROGRAM=$makeProgram',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DCMAKE_C_VISIBILITY_PRESET=hidden',
      '-DCMAKE_VISIBILITY_INLINES_HIDDEN=ON',
      '-DCMAKE_C_FLAGS=${cFlags.join(' ')}',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DBUILD_TESTS=OFF',
      '-DBUILD_CLI=OFF',
      '-DBUILD_EXAMPLES=OFF',
      '-DBUILD_FUZZERS=OFF',
      '-DUSE_THREADS=ON',
      '-DUSE_SSH=OFF',
      '-DUSE_HTTPS=$httpsBackend',
      '-DUSE_GSSAPI=OFF',
      '-DUSE_NTLMCLIENT=OFF',
      '-DUSE_BUNDLED_ZLIB=ON',
      '-DUSE_HTTP_PARSER=builtin',
      '-DREGEX_BACKEND=builtin',
      '-DUSE_ICONV=OFF',
      '-DUSE_SHA1=CollisionDetection',
      '-DUSE_SHA256=Builtin',
      '-DEXPERIMENTAL_SHA256=OFF',
      '-DDEBUG_STRICT_OPEN=ON',
      '-DDEPRECATE_HARD=ON',
      '-DENABLE_REPRODUCIBLE_BUILDS=OFF',
      '-DSONAME=ON',
      '-DSTATIC_CRT=OFF',
      if (cCompiler != null) '-DCMAKE_C_COMPILER=$cCompiler',
      if (sanitizerCompilerFlags.isNotEmpty)
        '-DCMAKE_SHARED_LINKER_FLAGS=${sanitizerCompilerFlags.join(' ')}',
      if (targetOS == NativeBuildTargetOS.macOS) ...<String>[
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=$macOSDeploymentTarget',
        '-DCMAKE_OSX_ARCHITECTURES=$cmakeArchitecture',
      ],
    ];
  }

  List<String> explicitShimArguments({
    required File libgit2Archive,
    required File output,
  }) => <String>[
    if (targetOS == NativeBuildTargetOS.macOS) '-dynamiclib' else '-shared',
    '-std=c11',
    '-fPIC',
    ...shimFlags,
    '-I${nativeIncludeDirectory.path}',
    '-I${libgit2IncludeDirectory.path}',
    ...shimSources.map((source) => source.path),
    libgit2Archive.path,
    for (final library in shimSystemLibraries) '-l$library',
    '-o',
    output.path,
  ];

  List<String> windowsShimCompilerArguments({
    required File libgit2Archive,
    required File output,
  }) {
    if (targetOS != NativeBuildTargetOS.windows) {
      throw StateError('Windows shim arguments require a Windows target.');
    }
    final outputDirectory = output.parent.path;
    return <String>[
      '/nologo',
      '/LD',
      '/O2',
      '/MD',
      '/std:c11',
      '/Fo$outputDirectory${Platform.pathSeparator}',
      '/Fd$outputDirectory${Platform.pathSeparator}skills_workspace_native.pdb',
      '/DRELEASE',
      '/DNDEBUG',
      '/DGIT_STATIC',
      '/DSHA1DC_FORCE_ALIGNED_ACCESS',
      '/I${nativeIncludeDirectory.path}',
      '/I${libgit2IncludeDirectory.path}',
      ...shimSources.map((source) => source.path),
      libgit2Archive.path,
      ...shimSystemLibraries,
      '/link',
      '/OUT:${output.path}',
      '/IMPLIB:$outputDirectory${Platform.pathSeparator}skills_workspace_native.lib',
      '/PDB:$outputDirectory${Platform.pathSeparator}skills_workspace_native_link.pdb',
    ];
  }

  String _path(String first, [String? second, String? third, String? fourth]) =>
      <String>[
        packageRoot.path,
        first,
        ?second,
        ?third,
        ?fourth,
      ].join(Platform.pathSeparator);

  String _outputPath(String child) =>
      <String>[outputDirectory.path, child].join(Platform.pathSeparator);
}

final class NativeLibraryBuilder {
  const NativeLibraryBuilder(this.policy);

  final NativeBuildPolicy policy;

  Future<File> buildLibgit2({
    String? cCompiler,
    String? cmakeExecutable,
    String? generator,
    String? makeProgram,
    Map<String, String>? environment,
    void Function(String message)? onOutput,
    void Function(String message)? onError,
  }) async {
    await policy.libgit2BuildDirectory.create(recursive: true);
    final cmake = cmakeExecutable ?? 'cmake';
    await _run(
      cmake,
      policy.libgit2ConfigureArguments(
        cCompiler: cCompiler,
        generator: generator,
        makeProgram: makeProgram,
      ),
      phase: 'configure pinned libgit2',
      environment: environment,
      onOutput: onOutput,
      onError: onError,
    );
    _verifyLibgit2Configuration(
      policy.libgit2BuildDirectory,
      required: policy.requiredLibgit2Features,
      forbidden: policy.forbiddenLibgit2Features,
    );
    await _run(
      cmake,
      <String>[
        '--build',
        policy.libgit2BuildDirectory.path,
        '--config',
        'Release',
        '--target',
        'libgit2package',
        '--parallel',
      ],
      phase: 'build pinned libgit2',
      environment: environment,
      onOutput: onOutput,
      onError: onError,
    );

    for (final candidate in <File>[
      File('${policy.libgit2BuildDirectory.path}/libgit2.a'),
      File('${policy.libgit2BuildDirectory.path}/git2.lib'),
      File('${policy.libgit2BuildDirectory.path}/Release/git2.lib'),
    ]) {
      if (candidate.existsSync()) {
        return candidate;
      }
    }
    throw StateError('The pinned libgit2 build produced no static archive.');
  }

  Future<File> buildWindowsDynamicLibrary({
    void Function(String message)? onOutput,
    void Function(String message)? onError,
  }) async {
    if (policy.targetOS != NativeBuildTargetOS.windows) {
      throw StateError('The Windows shim builder requires a Windows target.');
    }
    await policy.outputDirectory.create(recursive: true);
    final toolchain = await _WindowsVisualStudioToolchain.resolve();
    final environment = await toolchain.developerEnvironment();
    final compiler = toolchain.compiler(environment);
    final archive = await buildLibgit2(
      cmakeExecutable: toolchain.cmake.path,
      generator: 'Ninja',
      makeProgram: toolchain.ninja.path,
      environment: environment,
      onOutput: onOutput,
      onError: onError,
    );
    final output = policy.dynamicLibrary;
    final compilerArguments = policy.windowsShimCompilerArguments(
      libgit2Archive: archive,
      output: output,
    );
    await _run(
      compiler.path,
      compilerArguments,
      phase: 'compile Windows native shim',
      environment: environment,
      onOutput: onOutput,
      onError: onError,
    );
    if (!output.existsSync()) {
      throw StateError('The Windows native build produced no dynamic library.');
    }
    return output;
  }

  Future<File> buildExplicitDynamicLibrary({required String cCompiler}) async {
    if (policy.targetOS == NativeBuildTargetOS.windows) {
      throw UnsupportedError(
        'Explicit sanitizer builds are supported only on macOS and Linux.',
      );
    }
    await policy.outputDirectory.create(recursive: true);
    final archive = await buildLibgit2(cCompiler: cCompiler);
    final output = policy.dynamicLibrary;
    await _run(
      cCompiler,
      policy.explicitShimArguments(libgit2Archive: archive, output: output),
      phase: 'link explicit native shim',
    );
    if (!output.existsSync()) {
      throw StateError(
        'The explicit native build produced no dynamic library.',
      );
    }
    return output;
  }
}

final class _WindowsVisualStudioToolchain {
  const _WindowsVisualStudioToolchain({
    required this.cmake,
    required this.ninja,
    required this.developerCommandPrompt,
  });

  final File cmake;
  final File ninja;
  final File developerCommandPrompt;

  File compiler(Map<String, String> environment) {
    final toolsRoot = _caseInsensitiveValue(environment, 'VCToolsInstallDir');
    if (toolsRoot == null) {
      throw StateError(
        'Visual Studio developer environment omitted VCToolsInstallDir.',
      );
    }
    final compiler = File(
      '$toolsRoot${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'Hostx64${Platform.pathSeparator}x64${Platform.pathSeparator}cl.exe',
    );
    if (!compiler.existsSync()) {
      throw StateError('The Visual Studio x64 compiler is missing.');
    }
    return compiler;
  }

  Future<Map<String, String>> developerEnvironment() async {
    // Dart escapes embedded quotes as \" on Windows, which cmd.exe does not
    // understand, so run the prompt from its own directory and name it bare
    // instead of quoting a path that usually contains spaces.
    final result = await Process.run('cmd.exe', const <String>[
      '/d',
      '/s',
      '/c',
      'call VsDevCmd.bat -arch=x64 -host_arch=x64 >nul && set',
    ], workingDirectory: developerCommandPrompt.parent.path);
    if (result.exitCode != 0) {
      throw StateError(
        'Visual Studio developer environment failed with exit code '
        '${result.exitCode}.',
      );
    }
    final environment = <String, String>{};
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      environment[line.substring(0, separator)] = line.substring(separator + 1);
    }
    for (final required in const <String>[
      'INCLUDE',
      'LIB',
      'PATH',
      'VCToolsInstallDir',
    ]) {
      if (_caseInsensitiveValue(environment, required) == null) {
        throw StateError(
          'Visual Studio developer environment omitted $required.',
        );
      }
    }
    return environment;
  }

  static Future<_WindowsVisualStudioToolchain> resolve() async {
    final configuredProgramFiles = _environmentValue('ProgramFiles(x86)');
    final systemDrive = _environmentValue('SystemDrive') ?? 'C:';
    final programFilesX86 = configuredProgramFiles?.trim().isNotEmpty == true
        ? configuredProgramFiles!.trim()
        : '$systemDrive${Platform.pathSeparator}Program Files (x86)';
    final vswhere = File(
      '$programFilesX86${Platform.pathSeparator}Microsoft Visual Studio'
      '${Platform.pathSeparator}Installer${Platform.pathSeparator}vswhere.exe',
    );
    if (!vswhere.existsSync()) {
      throw StateError('Visual Studio discovery is unavailable.');
    }
    final process = await Process.start(vswhere.path, const <String>[
      '-latest',
      '-products',
      '*',
      '-requires',
      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
      '-property',
      'installationPath',
      '-utf8',
    ]);
    final standardOutput = await process.stdout.transform(utf8.decoder).join();
    final standardError = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw StateError(
        'Visual Studio discovery failed with exit code $exitCode.'
        '${standardError.trim().isEmpty ? '' : ' Output was produced.'}',
      );
    }
    final installations = const LineSplitter()
        .convert(standardOutput)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (installations.isEmpty) {
      throw StateError('No compatible Visual Studio installation was found.');
    }
    final root = installations.last;
    final cmake = File(
      '$root${Platform.pathSeparator}Common7${Platform.pathSeparator}IDE'
      '${Platform.pathSeparator}CommonExtensions${Platform.pathSeparator}'
      'Microsoft${Platform.pathSeparator}CMake${Platform.pathSeparator}CMake'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}cmake.exe',
    );
    final ninja = File(
      '$root${Platform.pathSeparator}Common7${Platform.pathSeparator}IDE'
      '${Platform.pathSeparator}CommonExtensions${Platform.pathSeparator}'
      'Microsoft${Platform.pathSeparator}CMake${Platform.pathSeparator}Ninja'
      '${Platform.pathSeparator}ninja.exe',
    );
    final developerCommandPrompt = File(
      '$root${Platform.pathSeparator}Common7${Platform.pathSeparator}Tools'
      '${Platform.pathSeparator}VsDevCmd.bat',
    );
    if (!cmake.existsSync() ||
        !ninja.existsSync() ||
        !developerCommandPrompt.existsSync()) {
      throw StateError('The Visual Studio C++ toolchain is incomplete.');
    }
    return _WindowsVisualStudioToolchain(
      cmake: cmake,
      ninja: ninja,
      developerCommandPrompt: developerCommandPrompt,
    );
  }
}

String? _environmentValue(String requested) {
  final normalized = requested.toLowerCase();
  for (final entry in Platform.environment.entries) {
    if (entry.key.toLowerCase() == normalized) {
      return entry.value;
    }
  }
  return null;
}

String? _caseInsensitiveValue(
  Map<String, String> environment,
  String requested,
) {
  final normalized = requested.toLowerCase();
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == normalized) return entry.value;
  }
  return null;
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String phase,
  Map<String, String>? environment,
  void Function(String message)? onOutput,
  void Function(String message)? onError,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: environment == null,
  );
  final standardOutput = (result.stdout as String).trim();
  if (standardOutput.isNotEmpty) {
    onOutput?.call(standardOutput);
  }
  final standardError = (result.stderr as String).trim();
  if (standardError.isNotEmpty) {
    onError?.call(standardError);
  }
  if (result.exitCode != 0) {
    throw StateError('$phase failed with exit code ${result.exitCode}.');
  }
}

void _verifyLibgit2Configuration(
  Directory buildDirectory, {
  required List<String> required,
  required List<String> forbidden,
}) {
  final featureHeader = File(
    '${buildDirectory.path}/gen_headers/git2_features.h',
  );
  if (!featureHeader.existsSync()) {
    throw StateError('The pinned libgit2 feature manifest is missing.');
  }

  final contents = featureHeader.readAsStringSync();
  for (final feature in forbidden) {
    if (RegExp(
      '^#define $feature(?:\\s|\$)',
      multiLine: true,
    ).hasMatch(contents)) {
      throw StateError('The pinned libgit2 build enabled a forbidden feature.');
    }
  }
  for (final feature in required) {
    if (!RegExp(
      '^#define $feature(?:\\s|\$)',
      multiLine: true,
    ).hasMatch(contents)) {
      throw StateError('The pinned libgit2 build omitted a required feature.');
    }
  }
}

const _forbiddenLibgit2Features = <String>[
  'GIT_USE_ICONV',
  'GIT_SSH',
  'GIT_SSH_EXEC',
  'GIT_SSH_LIBSSH2',
  'GIT_SSH_LIBSSH2_MEMORY_CREDENTIALS',
  'GIT_NTLM',
  'GIT_GSSAPI',
  'GIT_GSSFRAMEWORK',
  'GIT_WINHTTP',
  'GIT_HTTPS',
  'GIT_OPENSSL',
  'GIT_OPENSSL_DYNAMIC',
  'GIT_SECURE_TRANSPORT',
  'GIT_MBEDTLS',
  'GIT_SCHANNEL',
];

const _requiredLibgit2Features = <String>[
  'GIT_THREADS',
  'GIT_DEBUG_STRICT_OPEN',
  'GIT_REGEX_BUILTIN',
  'GIT_HTTPPARSER_BUILTIN',
  'GIT_SHA1_COLLISIONDETECT',
  'GIT_SHA256_BUILTIN',
  'GIT_COMPRESSION_BUILTIN',
];
