import 'dart:io';

import 'package:test/test.dart';

import '../../tool/native_build_policy.dart';

void main() {
  group('NativeSanitizerConfiguration', () {
    test('normalizes supported names into deterministic flag order', () {
      final configuration = NativeSanitizerConfiguration.parse(
        ' undefined, address,address ',
      );

      expect(configuration.serialized, 'address,undefined');
      expect(configuration.compilerFlags(NativeBuildTargetOS.macOS), <String>[
        '-fsanitize=address,undefined',
        '-fno-omit-frame-pointer',
      ]);
    });

    test('represents none without compiler flags', () {
      final configuration = NativeSanitizerConfiguration.parse('none');

      expect(configuration.isEnabled, isFalse);
      expect(configuration.serialized, 'none');
      expect(configuration.compilerFlags(NativeBuildTargetOS.windows), isEmpty);
    });

    test('rejects unsupported names and sanitizer builds on Windows', () {
      expect(
        () => NativeSanitizerConfiguration.parse('thread'),
        throwsArgumentError,
      );
      expect(
        () => NativeSanitizerConfiguration.parse(
          'address',
        ).compilerFlags(NativeBuildTargetOS.windows),
        throwsUnsupportedError,
      );
    });
  });

  group('NativeBuildPolicy', () {
    test('enables libgit2 thread-safe lifecycle support', () {
      final configure = _policy(
        targetOS: NativeBuildTargetOS.macOS,
        targetArchitecture: NativeBuildArchitecture.arm64,
        sanitizers: NativeSanitizerConfiguration.none,
      ).libgit2ConfigureArguments();

      expect(configure, contains('-DUSE_THREADS=ON'));
      expect(configure, isNot(contains('-DUSE_THREADS=OFF')));
      expect(configure, isNot(contains('--fresh')));
    });

    test('selects the platform HTTPS backend and keeps SSH disabled', () {
      final expected = <NativeBuildTargetOS, (String, List<String>)>{
        NativeBuildTargetOS.macOS: (
          'SecureTransport',
          <String>['GIT_HTTPS', 'GIT_SECURE_TRANSPORT'],
        ),
        NativeBuildTargetOS.linux: (
          'OpenSSL-Dynamic',
          <String>['GIT_HTTPS', 'GIT_OPENSSL', 'GIT_OPENSSL_DYNAMIC'],
        ),
        NativeBuildTargetOS.windows: (
          'WinHTTP',
          <String>['GIT_HTTPS', 'GIT_WINHTTP'],
        ),
      };
      for (final MapEntry(key: targetOS, value: (backend, features))
          in expected.entries) {
        final policy = _policy(
          targetOS: targetOS,
          targetArchitecture: NativeBuildArchitecture.x64,
          sanitizers: NativeSanitizerConfiguration.none,
        );
        final configure = policy.libgit2ConfigureArguments();

        expect(configure, contains('-DUSE_HTTPS=$backend'));
        expect(configure, contains('-DUSE_SSH=OFF'));
        expect(configure, contains('-DUSE_SHA1=CollisionDetection'));
        expect(policy.requiredLibgit2Features, containsAll(features));
        expect(
          policy.forbiddenLibgit2Features.toSet().intersection(
            policy.requiredLibgit2Features.toSet(),
          ),
          isEmpty,
        );
        expect(
          policy.forbiddenLibgit2Features,
          containsAll(<String>['GIT_SSH', 'GIT_NTLM', 'GIT_MBEDTLS']),
        );
      }
    });

    test('links only the system libraries of the chosen backend', () {
      final macOS = _policy(
        targetOS: NativeBuildTargetOS.macOS,
        targetArchitecture: NativeBuildArchitecture.arm64,
        sanitizers: NativeSanitizerConfiguration.none,
      );
      expect(macOS.shimFrameworks, <String>['Security', 'CoreFoundation']);
      expect(macOS.shimSystemLibraries, isEmpty);
      // CBuilder applies `frameworks` only to Objective-C, so the C shim
      // receives them as linker flags on both the hook and explicit paths.
      expect(
        macOS.shimFlags,
        containsAll(<String>[
          '-Wl,-framework,Security',
          '-Wl,-framework,CoreFoundation',
        ]),
      );

      final linux = _policy(
        targetOS: NativeBuildTargetOS.linux,
        targetArchitecture: NativeBuildArchitecture.x64,
        sanitizers: NativeSanitizerConfiguration.none,
      );
      expect(linux.shimFrameworks, isEmpty);
      expect(
        linux.explicitShimArguments(
          libgit2Archive: File('/output/libgit2.a'),
          output: File('/output/libskills_workspace_native.so'),
        ),
        contains('-ldl'),
      );
    });

    test('uses one sanitizer flag set for libgit2 and the dynamic shim', () {
      final policy = _policy(
        targetOS: NativeBuildTargetOS.macOS,
        targetArchitecture: NativeBuildArchitecture.arm64,
        sanitizers: NativeSanitizerConfiguration.parse('address,undefined'),
      );

      final configure = policy.libgit2ConfigureArguments(cCompiler: 'clang');
      final shim = policy.explicitShimArguments(
        libgit2Archive: File('/output/libgit2.a'),
        output: File('/output/libskills_workspace_native.dylib'),
      );

      expect(
        configure,
        contains(
          '-DCMAKE_C_FLAGS=-DSHA1DC_FORCE_ALIGNED_ACCESS '
          '-fsanitize=address,undefined '
          '-fno-omit-frame-pointer',
        ),
      );
      expect(configure, contains('-DCMAKE_C_COMPILER=clang'));
      expect(shim, containsAll(policy.sanitizerCompilerFlags));
      expect(shim, contains('-mmacos-version-min=11.0'));
      expect(shim, contains('-dynamiclib'));
    });

    test('keeps ordinary Windows Native Assets builds sanitizer-free', () {
      final policy = _policy(
        targetOS: NativeBuildTargetOS.windows,
        targetArchitecture: NativeBuildArchitecture.x64,
        sanitizers: NativeSanitizerConfiguration.none,
      );

      final configure = policy.libgit2ConfigureArguments(
        generator: 'Ninja',
        makeProgram: r'C:\Visual Studio\CMake\Ninja\ninja.exe',
      );

      expect(policy.shimFlags, isEmpty);
      expect(configure, isNot(contains(contains('fsanitize'))));
      expect(
        configure,
        contains(
          '-DCMAKE_C_FLAGS=/DGIT_STATIC '
          '/DSHA1DC_FORCE_ALIGNED_ACCESS',
        ),
      );
      expect(
        configure,
        containsAllInOrder(<String>[
          '-G',
          'Ninja',
          '-S',
          policy.libgit2SourceDirectory.path,
        ]),
      );
      expect(
        configure,
        contains(
          r'-DCMAKE_MAKE_PROGRAM=C:\Visual Studio\CMake\Ninja\ninja.exe',
        ),
      );
      final arguments = policy.windowsShimCompilerArguments(
        libgit2Archive: File('/output/git2.lib'),
        output: File('/output/skills_workspace_native.dll'),
      );
      expect(
        arguments,
        containsAll(<String>[
          '/LD',
          '/O2',
          '/MD',
          '/std:c11',
          '/DGIT_STATIC',
          '/DSHA1DC_FORCE_ALIGNED_ACCESS',
        ]),
      );
      expect(arguments, contains('/output/git2.lib'));
      expect(
        arguments,
        containsAll(<String>[
          'ws2_32.lib',
          'secur32.lib',
          'advapi32.lib',
          'winhttp.lib',
          'rpcrt4.lib',
          'crypt32.lib',
          'ole32.lib',
        ]),
      );
      expect(arguments, contains('/OUT:/output/skills_workspace_native.dll'));
      expect(arguments, contains('/Fo/output${Platform.pathSeparator}'));
      expect(
        arguments,
        contains(
          '/IMPLIB:/output${Platform.pathSeparator}skills_workspace_native.lib',
        ),
      );
    });

    test('applies the Linux export allowlist to the explicit shim', () {
      final policy = _policy(
        targetOS: NativeBuildTargetOS.linux,
        targetArchitecture: NativeBuildArchitecture.x64,
        sanitizers: NativeSanitizerConfiguration.parse('undefined'),
      );

      expect(policy.dynamicLibrary.path, endsWith('.so'));
      expect(policy.shimFlags, contains('-D_GNU_SOURCE'));
      expect(policy.shimFlags, contains(contains('--version-script=')));
      expect(
        policy.shimFlags,
        contains('-Wl,-soname,libskills_workspace_native.so'),
      );
      expect(policy.shimFlags, contains('-Wl,-s'));
      expect(policy.shimFlags, contains('-fsanitize=undefined'));
    });

    test('expresses the supported macOS deployment floors', () {
      final arm64Policy = _policy(
        targetOS: NativeBuildTargetOS.macOS,
        targetArchitecture: NativeBuildArchitecture.arm64,
        sanitizers: NativeSanitizerConfiguration.none,
      );
      expect(arm64Policy.macOSDeploymentTarget, '11.0');
      expect(arm64Policy.shimFlags, containsAll(<String>['-Wl,-S', '-Wl,-x']));
      expect(
        _policy(
          targetOS: NativeBuildTargetOS.macOS,
          targetArchitecture: NativeBuildArchitecture.x64,
          sanitizers: NativeSanitizerConfiguration.none,
        ).macOSDeploymentTarget,
        '10.15',
      );
    });
  });
}

NativeBuildPolicy _policy({
  required NativeBuildTargetOS targetOS,
  required NativeBuildArchitecture targetArchitecture,
  required NativeSanitizerConfiguration sanitizers,
}) => NativeBuildPolicy(
  packageRoot: Directory('/package'),
  outputDirectory: Directory('/output'),
  targetOS: targetOS,
  targetArchitecture: targetArchitecture,
  sanitizers: sanitizers,
);
