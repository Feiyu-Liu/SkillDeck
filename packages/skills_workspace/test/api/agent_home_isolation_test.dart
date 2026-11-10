import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test(
    'explicit agent home excludes ambient native and shared home overrides',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agent-home-isolation-',
      );
      addTearDown(() => root.delete(recursive: true));
      final outside = path.join(root.path, 'outside');
      final skill = File(
        path.join(outside, 'skills', 'outside-marker', 'SKILL.md'),
      );
      await skill.parent.create(recursive: true);
      await skill.writeAsString(
        '---\nname: outside-marker\ndescription: Must remain outside discovery.\n---\nMarker.\n',
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'test/fixtures/agent_home_isolation_probe.dart', root.path],
        environment: {
          for (final key in [
            'GROK_HOME',
            'SARVAM_HOME',
            'REASONIX_HOME',
            'DSH_HOME',
            'DSH_AGENTS_HOME',
            'APPDATA',
          ])
            key: outside,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(await skill.exists(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
