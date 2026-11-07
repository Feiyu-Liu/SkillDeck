import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.absolute;
  final generatedBindings = File(
    path.join(
      packageRoot.path,
      'lib',
      'src',
      'native',
      'generated',
      'skills_workspace_bindings_generated.dart',
    ),
  );
  final posixAdapter = File(
    path.join(
      packageRoot.path,
      'lib',
      'src',
      'platform',
      'filesystem',
      'posix_filesystem_primitives.dart',
    ),
  );

  test('ffigen owns every private POSIX durability binding', () {
    final ffigenConfiguration = File(
      path.join(packageRoot.path, 'ffigen.yaml'),
    ).readAsStringSync();
    final generatedSource = generatedBindings.readAsStringSync();
    final adapterSource = posixAdapter.readAsStringSync();
    const expectedSymbols = <String>[
      'skills_workspace_posix_write_new_at',
      'skills_workspace_posix_flush_path',
      'skills_workspace_posix_flush_at',
      'skills_workspace_posix_stat',
      'skills_workspace_posix_chmod',
      'skills_workspace_posix_rename_at',
      'skills_workspace_posix_exchange_at',
    ];

    for (final symbol in expectedSymbols) {
      expect(
        generatedSource,
        contains('external int $symbol('),
        reason: '$symbol must be emitted by ffigen',
      );
    }
    expect(
      ffigenConfiguration,
      contains("- 'skills_workspace_posix_.*'"),
      reason: 'clean regeneration must retain the POSIX shim surface',
    );
    expect(adapterSource, isNot(contains('@ffi.Native')));
    expect(
      adapterSource,
      contains(
        "../../native/generated/skills_workspace_bindings_generated.dart",
      ),
    );
  });

  test('the generated POSIX boundary stays private', () {
    final publicBarrel = File(
      path.join(packageRoot.path, 'lib', 'skills_workspace.dart'),
    ).readAsStringSync();

    expect(publicBarrel, isNot(contains('bindings_generated.dart')));
    expect(
      path.relative(generatedBindings.path, from: packageRoot.path),
      startsWith(path.join('lib', 'src', 'native', 'generated')),
    );
  });
}
