import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/command_host/data/skill_json.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

import 'support/read_fixtures.dart';

void main() {
  Future<Object?> golden(String name) async => jsonDecode(
    await File('test/features/command_host/fixtures/$name.json').readAsString(),
  );
  test(
    'skill projection golden excludes internal storage and strips userinfo',
    () async {
      final snapshot = testSnapshot();
      final skill = snapshot.skills.first;
      final json = skillJson(
        skill,
        snapshot,
        update: testUpdates().stateOf(skill.id),
      );
      expect(json, await golden('skill'));
      final text = jsonEncode(json);
      for (final secret in [
        'user:',
        'password',
        '/private',
        'git-oid',
        'private-ref',
        'private-subpath',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    },
  );
  test(
    'agent projection golden deduplicates global roots and uses membership',
    () async {
      expect(
        agentJson(
          testAgent(),
          memberIds: {'codex'},
          globalTargets: [
            testGlobalTarget,
            testGlobalTarget,
            const WorkspaceActivationTarget(
              agentId: 'codex',
              displayName: 'Codex',
              detected: true,
              location: '/project',
              scope: WorkspaceScope.project,
            ),
          ],
        ),
        await golden('agent'),
      );
      expect(
        agentJson(testAgent(), memberIds: {}, globalTargets: [])['enabled'],
        false,
      );
    },
  );
  test('project root projection golden', () async {
    expect(
      projectRootJson(testSnapshot().projectRoots.single),
      await golden('project_root'),
    );
  });
  test('userinfo sanitizer preserves paths, ports and query strings', () {
    for (final (input, expected) in [
      (
        'https://user:password@example.test:443/path?q=1#x',
        'https://example.test:443/path?q=1#x',
      ),
      ('ssh://git@example.test/repo', 'ssh://example.test/repo'),
      ('https://one@two@example.test/repo', 'https://example.test/repo'),
      ('/local/user@host/skill', '/local/user@host/skill'),
      ('https://example.test/repo', 'https://example.test/repo'),
    ]) {
      expect(stripLocatorUserinfo(input), expected);
    }
  });
  test('default, checking and failed observations remain distinct', () {
    final skill = testSkill(draft: false, tags: []);
    final snapshot = testSnapshot(skills: [skill]);
    expect(skillJson(skill, snapshot)['update'], {'status': 'notChecked'});
    expect(
      skillJson(skill, snapshot, update: const SkillUpdateChecking())['update'],
      {'status': 'checking'},
    );
    expect(
      skillJson(
        skill,
        snapshot,
        update: const SkillUpdateCheckFailed(
          UnexpectedAppFailure(operationKey: 'checkUpdates'),
        ),
      )['update'],
      {'status': 'checkFailed'},
    );
    expect(skillJson(skill, snapshot)['draft'], {'present': false});
  });
}
