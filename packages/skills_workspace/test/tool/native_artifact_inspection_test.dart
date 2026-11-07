import 'package:test/test.dart';

import '../../tool/native_artifact_inspection.dart';

void main() {
  group('NativeArtifactInspectionOptions', () {
    test('defaults to shim and parses SQLite evidence options', () {
      final shim = NativeArtifactInspectionOptions.parse(const <String>[
        '--artifact',
        '/tmp/libskills_workspace_native.dylib',
        '--architecture',
        'universal',
      ]);
      final sqlite = NativeArtifactInspectionOptions.parse(const <String>[
        '--kind',
        'sqlite',
        '--artifact',
        '/tmp/libsqlite3.dylib',
        '--macos-min',
        '13.0',
        '--architecture',
        'universal',
        '--report',
        '/tmp/sqlite.json',
      ]);

      expect(shim.kind, NativeArtifactKind.shim);
      expect(sqlite.kind, NativeArtifactKind.sqlite);
      expect(sqlite.minimumMacOS, {'13.0'});
      expect(sqlite.reportPath, '/tmp/sqlite.json');
    });

    test('rejects missing values, unsupported kinds, and architectures', () {
      expect(
        () =>
            NativeArtifactInspectionOptions.parse(const <String>['--artifact']),
        throwsFormatException,
      );
      expect(
        () => NativeArtifactInspectionOptions.parse(const <String>[
          '--artifact',
          'sqlite3',
          '--architecture',
          'x64',
          '--kind',
          'database',
        ]),
        throwsFormatException,
      );
      expect(
        () => NativeArtifactInspectionOptions.parse(const <String>[
          '--artifact',
          'sqlite3',
          '--architecture',
          'ia32',
        ]),
        throwsFormatException,
      );
    });
  });

  group('platform output parsers', () {
    test(
      'parses universal Mach-O identity, dependencies, RPATH, and min OS',
      () {
        const installOutput = '''
/release/sqlite3 (architecture x86_64):
@rpath/sqlite3.framework/sqlite3
/release/sqlite3 (architecture arm64):
@rpath/sqlite3.framework/sqlite3
''';
        const dependencyOutput = '''
/release/sqlite3 (architecture x86_64):
\t@rpath/sqlite3.framework/sqlite3 (compatibility version 0.0.0)
\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)
''';
        const commands = '''
Load command 4
          cmd LC_RPATH
      cmdsize 48
         path /Users/developer/lib (offset 12)
''';
        const build = '''
/release/sqlite3 (architecture x86_64):
    minos 13.0
/release/sqlite3 (architecture arm64):
    minos 13.0
''';

        final installNames = parseMachOInstallNames(installOutput);
        expect(parseLipoArchitectures('x86_64 arm64'), {'x86_64', 'arm64'});
        expect(installNames, {'@rpath/sqlite3.framework/sqlite3'});
        expect(
          parseMachODependencies(dependencyOutput, installNames: installNames),
          ['/usr/lib/libSystem.B.dylib'],
        );
        expect(parseMachORuntimeSearchPaths(commands), {
          '/Users/developer/lib',
        });
        expect(parseMachOMinimumTargets(build), {'13.0'});
        expect(
          parseShimExports('''
0000000000001000 T _skills_workspace_revision_init
0000000000002000 T _unexpected_debug_export
''', leadingUnderscore: true),
          {'skills_workspace_revision_init', 'unexpected_debug_export'},
        );
      },
    );

    test('parses ELF identity, dependencies, RPATH, and resolved paths', () {
      const dynamic = '''
 0x0000000000000001 (NEEDED)             Shared library: [libm.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x000000000000000e (SONAME)             Library soname: [libsqlite3.so]
 0x000000000000001d (RUNPATH)            Library runpath: [\$ORIGIN:/home/me/lib]
''';
      const resolved = '''
\tlibm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x0)
\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0)
\t/lib64/ld-linux-x86-64.so.2 (0x0)
''';

      expect(
        parseLinuxArchitectures(
          'Machine:                           Advanced Micro Devices X86-64',
        ),
        {'x86_64'},
      );
      expect(parseElfDependencies(dynamic), ['libc.so.6', 'libm.so.6']);
      expect(parseElfInstallNames(dynamic), {'libsqlite3.so'});
      expect(parseElfRuntimeSearchPaths(dynamic), {'\$ORIGIN', '/home/me/lib'});
      expect(parseLddResolvedPaths(resolved), {
        '/lib/x86_64-linux-gnu/libm.so.6',
        '/lib/x86_64-linux-gnu/libc.so.6',
        '/lib64/ld-linux-x86-64.so.2',
      });
      expect(
        parseShimExports('''
0000000000000000 A SKILLS_WORKSPACE_1.0
0000000000001000 T skills_workspace_revision_init@@SKILLS_WORKSPACE_1.0
0000000000002000 T git_libgit2_init@LIBGIT2_1.9
'''),
        {'skills_workspace_revision_init', 'git_libgit2_init'},
      );
    });

    test('parses PE architecture, dependencies, and every named export', () {
      const headers = '            8664 machine (x64)';
      const dependencies = '''
  Image has the following dependencies:

    KERNEL32.dll
    api-ms-win-crt-runtime-l1-1-0.dll
''';
      const exports = '''
    ordinal hint RVA      name

          1    0 00001000 skills_workspace_revision_init
          2    1 00002000 git_libgit2_init
          3    2 00003000 ?decorated@@YAHXZ
          4    3 00004000 forwarded = KERNEL32.Sleep
          5    4 00005000 [NONAME]

  Summary
        1000 .data
''';

      expect(parseWindowsArchitectures(headers), {'x86_64'});
      expect(parseWindowsDependencies(dependencies), [
        'KERNEL32.dll',
        'api-ms-win-crt-runtime-l1-1-0.dll',
      ]);
      expect(parseWindowsExports(exports), {
        'skills_workspace_revision_init',
        'git_libgit2_init',
        '?decorated@@YAHXZ',
        'forwarded',
        '#ordinal:5',
      });
    });
  });

  group('artifact policy', () {
    test('accepts the package-owned universal macOS SQLite shape', () {
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.macOS,
        kind: NativeArtifactKind.sqlite,
        artifactPath: '/release/sqlite3.framework/Versions/A/sqlite3',
        architecture: 'universal',
        expectedExports: const <String>{},
        expectedMinimumMacOS: const <String>{'13.0'},
        facts: _facts(
          architectures: const <String>{'arm64', 'x86_64'},
          dependencies: const <String>['/usr/lib/libSystem.B.dylib'],
          installNames: const <String>['@rpath/sqlite3.framework/sqlite3'],
          minimumTargets: const <String>['13.0'],
        ),
      );
    });

    test('SQLite does not consume or validate the shim export allowlist', () {
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.macOS,
          kind: NativeArtifactKind.sqlite,
          artifactPath: '/release/sqlite3.framework/Versions/A/sqlite3',
          architecture: 'universal',
          expectedExports: const <String>{'sqlite3_open'},
          expectedMinimumMacOS: const <String>{'13.0'},
          facts: _facts(
            architectures: const <String>{'arm64', 'x86_64'},
            dependencies: const <String>['/usr/lib/libSystem.B.dylib'],
            installNames: const <String>['@rpath/sqlite3.framework/sqlite3'],
            minimumTargets: const <String>['13.0'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
    });

    test('rejects external libraries, user RPATHs, and user resolutions', () {
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.macOS,
          kind: NativeArtifactKind.sqlite,
          artifactPath: '/release/sqlite3.framework/Versions/A/sqlite3',
          architecture: 'universal',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{'13.0'},
          facts: _facts(
            architectures: const <String>{'arm64', 'x86_64'},
            dependencies: const <String>['/opt/homebrew/lib/libcrypto.3.dylib'],
            installNames: const <String>['@rpath/sqlite3.framework/sqlite3'],
            minimumTargets: const <String>['13.0'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.macOS,
          kind: NativeArtifactKind.sqlite,
          artifactPath: '/release/sqlite3.framework/Versions/A/sqlite3',
          architecture: 'universal',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{'13.0'},
          facts: _facts(
            architectures: const <String>{'arm64', 'x86_64'},
            dependencies: const <String>['/usr/lib/libSystem.B.dylib'],
            installNames: const <String>['@rpath/sqlite3.framework/sqlite3'],
            rpaths: const <String>['/Users/developer/lib'],
            minimumTargets: const <String>['13.0'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.linux,
          kind: NativeArtifactKind.sqlite,
          artifactPath: '/release/libsqlite3.so',
          architecture: 'x64',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{},
          facts: _facts(
            dependencies: const <String>['libc.so.6', 'libm.so.6'],
            installNames: const <String>['libsqlite3.so'],
            resolvedPaths: const <String>['/home/user/lib/libc.so.6'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
    });

    test('accepts explicit Linux and Windows SQLite system allowlists', () {
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.linux,
        kind: NativeArtifactKind.sqlite,
        artifactPath: '/release/libsqlite3.so',
        architecture: 'x64',
        expectedExports: const <String>{},
        expectedMinimumMacOS: const <String>{},
        facts: _facts(
          dependencies: const <String>['libc.so.6', 'libm.so.6'],
          installNames: const <String>['libsqlite3.so'],
          resolvedPaths: const <String>[
            '/lib/x86_64-linux-gnu/libc.so.6',
            '/lib/x86_64-linux-gnu/libm.so.6',
          ],
        ),
      );
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.windows,
        kind: NativeArtifactKind.sqlite,
        artifactPath: r'C:\release\sqlite3.dll',
        architecture: 'x64',
        expectedExports: const <String>{},
        expectedMinimumMacOS: const <String>{},
        facts: _facts(
          dependencies: const <String>[
            'KERNEL32.dll',
            'api-ms-win-crt-runtime-l1-1-0.dll',
          ],
        ),
      );
    });

    test('accepts the HTTPS backend libraries for the shim only', () {
      const macOSShimDependencies = <String>[
        '/usr/lib/libSystem.B.dylib',
        '/System/Library/Frameworks/Security.framework/Versions/A/Security',
        '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/'
            'CoreFoundation',
      ];
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.macOS,
        kind: NativeArtifactKind.shim,
        artifactPath: '/release/libskills_workspace_native.dylib',
        architecture: 'arm64',
        expectedExports: const <String>{},
        expectedMinimumMacOS: const <String>{'11.0'},
        facts: _facts(
          architectures: const <String>{'arm64'},
          dependencies: macOSShimDependencies,
          installNames: const <String>[
            '@rpath/libskills_workspace_native.dylib',
          ],
          minimumTargets: const <String>['11.0'],
        ),
      );
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.windows,
        kind: NativeArtifactKind.shim,
        artifactPath: r'C:\release\skills_workspace_native.dll',
        architecture: 'x64',
        expectedExports: const <String>{},
        expectedMinimumMacOS: const <String>{},
        facts: _facts(
          dependencies: const <String>[
            'KERNEL32.dll',
            'WINHTTP.dll',
            'CRYPT32.dll',
            'RPCRT4.dll',
            'ole32.dll',
          ],
        ),
      );
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.windows,
          kind: NativeArtifactKind.sqlite,
          artifactPath: r'C:\release\sqlite3.dll',
          architecture: 'x64',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{},
          facts: _facts(
            dependencies: const <String>['KERNEL32.dll', 'WINHTTP.dll'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.linux,
          kind: NativeArtifactKind.shim,
          artifactPath: '/release/libskills_workspace_native.so',
          architecture: 'x64',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{},
          facts: _facts(
            dependencies: const <String>['libc.so.6', 'libssl.so.3'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
    });

    test('accepts only the bundle-local Linux origin runtime path', () {
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.linux,
        kind: NativeArtifactKind.shim,
        artifactPath: '/release/libskills_workspace_native.so',
        architecture: 'x64',
        expectedExports: const <String>{
          'skills_workspace_native_ping',
          'skills_workspace_revision_init',
        },
        expectedMinimumMacOS: const <String>{},
        facts: _facts(
          exports: const <String>{
            'skills_workspace_native_ping',
            'skills_workspace_revision_init',
          },
          installNames: const <String>['libskills_workspace_native.so'],
          rpaths: const <String>[r'$ORIGIN'],
        ),
      );

      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.linux,
          kind: NativeArtifactKind.shim,
          artifactPath: '/release/libskills_workspace_native.so',
          architecture: 'x64',
          expectedExports: const <String>{
            'skills_workspace_native_ping',
            'skills_workspace_revision_init',
          },
          expectedMinimumMacOS: const <String>{},
          facts: _facts(
            exports: const <String>{
              'skills_workspace_native_ping',
              'skills_workspace_revision_init',
            },
            installNames: const <String>['libskills_workspace_native.so'],
            rpaths: const <String>[r'$ORIGIN', '/home/developer/lib'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
    });

    test('accepts bundled Linux SQLite without a SONAME', () {
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.linux,
        kind: NativeArtifactKind.sqlite,
        artifactPath: '/release/libsqlite3.so',
        architecture: 'x64',
        expectedExports: const <String>{},
        expectedMinimumMacOS: const <String>{},
        facts: _facts(
          dependencies: const <String>['libc.so.6'],
          resolvedPaths: const <String>['/lib/x86_64-linux-gnu/libc.so.6'],
        ),
      );
    });

    test(
      'rejects an unexpected system library and external version stores',
      () {
        for (final dependency in const <String>['D3D12.dll', 'libgit2.so']) {
          expect(
            () => validateNativeArtifactFacts(
              platform: NativeArtifactPlatform.windows,
              kind: NativeArtifactKind.sqlite,
              artifactPath: r'C:\release\sqlite3.dll',
              architecture: 'x64',
              expectedExports: const <String>{},
              expectedMinimumMacOS: const <String>{},
              facts: _facts(dependencies: <String>[dependency]),
            ),
            throwsA(isA<NativeArtifactInspectionException>()),
          );
        }
      },
    );

    test('rejects every unexpected Windows shim export', () {
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.windows,
          kind: NativeArtifactKind.shim,
          artifactPath: r'C:\release\skills_workspace_native.dll',
          architecture: 'x64',
          expectedExports: const <String>{'skills_workspace_revision_init'},
          expectedMinimumMacOS: const <String>{},
          facts: _facts(
            exports: const <String>{
              'skills_workspace_revision_init',
              'git_libgit2_init',
            },
          ),
        ),
        throwsA(
          isA<NativeArtifactInspectionException>().having(
            (error) => error.message,
            'message',
            contains('git_libgit2_init'),
          ),
        ),
      );
    });

    test('accepts the exact Windows shim export allowlist', () {
      validateNativeArtifactFacts(
        platform: NativeArtifactPlatform.windows,
        kind: NativeArtifactKind.shim,
        artifactPath: r'C:\release\skills_workspace_native.dll',
        architecture: 'x64',
        expectedExports: const <String>{
          'skills_workspace_native_ping',
          'skills_workspace_revision_init',
        },
        expectedMinimumMacOS: const <String>{},
        facts: _facts(
          exports: const <String>{
            'skills_workspace_native_ping',
            'skills_workspace_revision_init',
          },
        ),
      );
    });

    test('requires exact macOS deployment targets and SQLite identity', () {
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.macOS,
          kind: NativeArtifactKind.sqlite,
          artifactPath: '/release/sqlite3.framework/Versions/A/sqlite3',
          architecture: 'universal',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{'10.15', '11.0'},
          facts: _facts(
            architectures: const <String>{'arm64', 'x86_64'},
            dependencies: const <String>['/usr/lib/libSystem.B.dylib'],
            installNames: const <String>['@rpath/sqlite3.framework/sqlite3'],
            minimumTargets: const <String>['13.0'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
      expect(
        () => validateNativeArtifactFacts(
          platform: NativeArtifactPlatform.macOS,
          kind: NativeArtifactKind.sqlite,
          artifactPath: '/release/sqlite3.framework/Versions/A/sqlite3',
          architecture: 'universal',
          expectedExports: const <String>{},
          expectedMinimumMacOS: const <String>{'13.0'},
          facts: _facts(
            architectures: const <String>{'arm64', 'x86_64'},
            dependencies: const <String>['/usr/lib/libSystem.B.dylib'],
            installNames: const <String>['/Users/me/libsqlite3.dylib'],
            minimumTargets: const <String>['13.0'],
          ),
        ),
        throwsA(isA<NativeArtifactInspectionException>()),
      );
    });
  });
}

NativeArtifactFacts _facts({
  Set<String> architectures = const <String>{'x86_64'},
  Set<String> exports = const <String>{},
  List<String> dependencies = const <String>[],
  List<String> installNames = const <String>[],
  List<String> rpaths = const <String>[],
  List<String> resolvedPaths = const <String>[],
  List<String> minimumTargets = const <String>[],
}) => NativeArtifactFacts(
  architectures: architectures,
  exports: exports,
  dynamicDependencies: dependencies,
  installNames: installNames,
  runtimeSearchPaths: rpaths,
  resolvedDependencyPaths: resolvedPaths,
  minimumDeploymentTargets: minimumTargets,
);
