import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/platform/activation/file_system_symbolic_link_capability.dart';
import 'package:test/test.dart';

void main() {
  test('probes beside the target and cleans all temporary artifacts', () async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-link-capability-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final supported = await const FileSystemSymbolicLinkCapability()
        .supportsSymbolicLinks(path.join(root.path, 'not-created', 'skills'));

    if (!Platform.isWindows) {
      expect(supported, isTrue);
    }
    expect(await root.list().toList(), isEmpty);
  });
}
