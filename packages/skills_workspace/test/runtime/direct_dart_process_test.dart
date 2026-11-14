import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../support/process/direct_dart_process.dart';

void main() {
  test(
    'raw child keeps its parent Native Assets after shared metadata changes',
    () async {
      final shared = File('.dart_tool/native_assets.yaml');
      final original = await shared.readAsString();
      final arguments = directDartScriptArguments(
        'test/support/process/revision_native_load_probe.dart',
      );
      final config = File(arguments[1].substring('--packages='.length));
      final copied =
          jsonDecode(await config.readAsString()) as Map<String, Object?>;
      for (final item in copied['packages']! as List<Object?>) {
        final entry = item! as Map<String, Object?>;
        expect(Uri.parse(entry['rootUri']! as String).isAbsolute, isTrue);
      }
      final ownMapping = File(
        path.join(config.parent.path, 'native_assets.yaml'),
      );
      expect(await ownMapping.exists(), isTrue);
      try {
        // Model another short-lived dartdev invocation changing shared metadata.
        await shared.writeAsString('{"native-assets": {}}');
        final result = await Process.run(
          Platform.resolvedExecutable,
          arguments,
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('1.9.7'));
        expect(
          await ownMapping.readAsString(),
          isNot(contains('"native-assets": {}')),
        );
      } finally {
        await shared.writeAsString(original);
      }
    },
  );
}
