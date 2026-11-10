import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  test('round trips locale and custom agent settings', () {
    const settings = AppSettings(
      localePreference: AppLocalePreference.en,
      suppressDuplicateActivationConfirmation: true,
      sidebarCollapsed: true,
      customAgents: [
        CustomAgentSettings(
          id: 'custom-reviewer-1234',
          displayName: 'Reviewer',
          iconName: 'bot',
          platforms: {
            AppDesktopPlatform.macos: CustomAgentPlatformSettings(
              globalSkillsPath: '/Users/me/.reviewer/skills',
              projectSkillsPath: '.reviewer/skills',
              globalDiscoverySkillsPaths: <String>[
                '/Users/me/.reviewer/legacy-skills',
              ],
              projectDiscoverySkillsPaths: <String>['.reviewer/legacy-skills'],
            ),
          },
        ),
      ],
    );
    expect(
      AppSettings.decode(jsonEncode(settings.toJson())).toJson(),
      settings.toJson(),
    );
  });

  test('rejects unsafe custom agent paths', () {
    expect(
      () =>
          CustomAgentPlatformSettings(globalSkillsPath: 'relative/path')
              .validate(),
      throwsFormatException,
    );
    expect(
      () =>
          CustomAgentPlatformSettings(projectSkillsPath: '../outside')
              .validate(),
      throwsFormatException,
    );
    expect(
      () => const CustomAgentPlatformSettings(
        globalSkillsPath: '/canonical',
        globalDiscoverySkillsPaths: <String>['relative/legacy'],
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const CustomAgentPlatformSettings(
        projectSkillsPath: '.canonical/skills',
        projectDiscoverySkillsPaths: <String>['../legacy'],
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const CustomAgentPlatformSettings(
        projectSkillsPath: '.canonical/skills',
        globalDiscoverySkillsPaths: <String>['/legacy'],
      ).validate(),
      throwsFormatException,
    );
  });

  test('older version-one settings default discovery aliases to empty', () {
    final settings = AppSettings.fromJson({
      'version': 1,
      'localePreference': 'system',
      'customAgents': [
        {
          'id': 'custom-reviewer-1234',
          'displayName': 'Reviewer',
          'iconName': 'bot',
          'platforms': {
            'linux': {'globalSkillsPath': '/opt/reviewer/skills'},
          },
        },
      ],
    });

    final platform = settings.customAgents.single.platforms.values.single;
    expect(platform.globalDiscoverySkillsPaths, isEmpty);
    expect(platform.projectDiscoverySkillsPaths, isEmpty);
    expect(settings.version, 1);
    expect(settings.suppressDuplicateActivationConfirmation, isFalse);
    expect(settings.sidebarCollapsed, isFalse);
    expect(
      settings.globalActivationMethod,
      WorkspaceActivationMethod.automatic,
    );
  });

  test('round trips every global activation method', () {
    for (final method in WorkspaceActivationMethod.values) {
      final settings = AppSettings.decode(
        jsonEncode(AppSettings(globalActivationMethod: method).toJson()),
      );
      expect(settings.globalActivationMethod, method);
    }
  });

  test('rejects an unknown global activation method', () {
    expect(
      () => AppSettings.fromJson({
        'version': 1,
        'localePreference': 'system',
        'globalActivationMethod': 'hardLink',
        'customAgents': [],
      }),
      throwsFormatException,
    );
  });

  test('rejects a non-boolean sidebar collapsed preference', () {
    expect(
      () => AppSettings.fromJson({
        'version': 1,
        'localePreference': 'system',
        'sidebarCollapsed': 'yes',
        'customAgents': [],
      }),
      throwsFormatException,
    );
  });

  test('ignores the legacy analytics opt-out preference', () {
    final settings = AppSettings.fromJson({
      'version': 1,
      'localePreference': 'system',
      'analyticsEnabled': false,
      'customAgents': const [],
    });

    expect(settings.toJson(), isNot(contains('analyticsEnabled')));
  });

  test('rejects an Agent ID outside the custom namespace', () {
    expect(
      () => AppSettings.fromJson({
        'version': 1,
        'localePreference': 'system',
        'customAgents': [
          {
            'id': 'codex',
            'displayName': 'Other Codex',
            'iconName': 'bot',
            'platforms': {
              'macos': {'globalSkillsPath': '/tmp/skills'},
            },
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
