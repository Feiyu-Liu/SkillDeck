import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/application/agents/built_in_agent_definitions.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  final home = path.join(Directory.systemTemp.path, 'catalog-home');
  final custom = path.join(home, 'custom');
  List<AgentDefinition> definitions(
    DesktopPlatform platform, [
    Map<String, String> overrides = const {},
  ]) => buildBuiltInAgentDefinitions(
    platform: platform,
    environment: {'HOME': home, ...overrides},
  );

  for (final platform in DesktopPlatform.values) {
    group(platform.name, () {
      AgentPlatformDefinition rules(
        String id, [
        Map<String, String> overrides = const {},
      ]) => definitions(
        platform,
        overrides,
      ).singleWhere((agent) => agent.id == id).onPlatform(platform)!;

      test('new agents have native targets and separate detection markers', () {
        final expected = {
          'grok': ('.grok/skills', '.grok/skills', '.grok'),
          'kimchi': (
            '.kimchi/skills',
            '.config/kimchi/harness/skills',
            '.config/kimchi',
          ),
          'minimax-code': ('.minimax/skills', '.minimax/skills', '.minimax'),
          'posit-assistant': (
            '.posit/assistant/skills',
            '.posit/assistant/skills',
            '.posit/assistant',
          ),
          'fx': ('.agents/skills', '.agents/skills', '.fx'),
          'sarvam-code': ('.agents/skills', '.agents/skills', '.sarvam'),
          'deepseek-harness': ('.dsh/skills', '.dsh/skills', '.dsh'),
          'workbuddy': ('.workbuddy/skills', '.workbuddy/skills', '.workbuddy'),
        };
        for (final entry in expected.entries) {
          final rule = rules(entry.key, {'XDG_CONFIG_HOME': custom});
          expect(rule.projectSkillsPath, entry.value.$1, reason: entry.key);
          expect(
            path.normalize(rule.globalSkillsPath!),
            path.normalize(path.join(home, entry.value.$2)),
            reason: entry.key,
          );
          expect(
            rule.detectionPaths,
            contains(
              AgentDetectionPath.absolute(path.join(home, entry.value.$3)),
            ),
            reason: entry.key,
          );
        }
        expect(
          rules('posit-assistant').detectionPaths,
          contains(AgentDetectionPath.absolute(path.join(home, '.positai'))),
        );
        expect(
          rules('minimax-code').detectionPaths,
          contains(
            AgentDetectionPath.absolute('/Applications/MiniMax Code.app'),
          ),
        );
      });

      test('environment overrides and blank values resolve consistently', () {
        for (final entry in {
          'grok': 'GROK_HOME',
          'sarvam-code': 'SARVAM_HOME',
          'reasonix': 'REASONIX_HOME',
        }.entries) {
          final rule = rules(entry.key, {entry.value: custom});
          expect(
            rule.detectionPaths,
            contains(AgentDetectionPath.absolute(custom)),
          );
          expect(
            path.normalize(rule.globalSkillsPath!),
            path.normalize(
              path.join(
                entry.key == 'sarvam-code'
                    ? path.join(home, '.agents')
                    : custom,
                'skills',
              ),
            ),
          );
          expect(rules(entry.key, {entry.value: '  '}), rules(entry.key));
        }
        final reasonixDefault = platform == DesktopPlatform.windows
            ? path.join(home, 'AppData', 'Roaming', 'reasonix')
            : path.join(home, '.reasonix');
        expect(
          path.normalize(rules('reasonix').globalSkillsPath!),
          path.join(reasonixDefault, 'skills'),
        );
        expect(
          path.normalize(
            rules('reasonix', {'APPDATA': custom}).globalSkillsPath!,
          ),
          platform == DesktopPlatform.windows
              ? path.join(custom, 'reasonix', 'skills')
              : path.join(reasonixDefault, 'skills'),
        );
        expect(rules('reasonix', {'APPDATA': '  '}), rules('reasonix'));
      });

      test(
        'Antigravity global target is not Universal and retains legacy discovery',
        () {
          for (final id in ['antigravity', 'antigravity-cli']) {
            final rule = rules(id);
            expect(
              path.normalize(rule.globalSkillsPath!),
              path.join(home, '.gemini', 'config', 'skills'),
            );
            expect(rule.projectSkillsPath, '.agents/skills');
            expect(
              rule.detectionPaths.map(
                (entry) => (
                  entry.kind,
                  path.normalize(entry.path),
                  entry.relativeToProject,
                  entry.dependencyName,
                ),
              ),
              [
                (
                  AgentDetectionKind.pathExists,
                  path.join(home, '.gemini', id),
                  false,
                  null,
                ),
              ],
            );
            expect(rule.globalDiscoverySkillsPaths.map(path.normalize), [
              path.join(home, '.gemini', id, 'skills'),
            ]);
          }
          final reasonix = rules('reasonix', {'REASONIX_HOME': custom});
          expect(reasonix.globalDiscoverySkillsPaths.map(path.normalize), [
            path.join(home, '.reasonix', 'skills'),
          ]);
          expect(
            rules(
              'reasonix',
            ).globalDiscoverySkillsPaths.map(path.normalize).toSet().length,
            rules('reasonix').globalDiscoverySkillsPaths.length,
          );
        },
      );

      test(
        'DeepSeek expands homes and separates shared discovery from writes',
        () {
          final rule = rules('deepseek-harness', {
            'DSH_HOME': '~/dsh',
            'DSH_AGENTS_HOME': '~\\shared',
          });
          expect(rule.globalSkillsPath, path.join(home, 'dsh', 'skills'));
          expect(rule.globalDiscoverySkillsPaths, [
            path.join(home, 'shared', 'skills'),
          ]);
          expect(rule.projectDiscoverySkillsPaths, ['.agents/skills']);
          expect(rule.detectionPaths, [
            AgentDetectionPath.absolute(path.join(home, 'dsh')),
          ]);
          expect(
            rules('deepseek-harness', {'DSH_HOME': ' ', 'DSH_AGENTS_HOME': ''}),
            rules('deepseek-harness'),
          );
          expect(
            rules('deepseek-harness', {
              'DSH_HOME': custom,
              'DSH_AGENTS_HOME': custom,
            }).globalDiscoverySkillsPaths,
            isEmpty,
          );
          expect(
            rules('deepseek-harness', {'DSH_HOME': '~'}).globalSkillsPath,
            path.join(home, 'skills'),
          );
          expect(
            () => rules('deepseek-harness', {'DSH_HOME': 'relative'}),
            throwsArgumentError,
          );
          expect(
            () => rules('deepseek-harness', {'DSH_AGENTS_HOME': 'relative'}),
            throwsArgumentError,
          );
        },
      );

      test('shared roots do not detect DeepSeek, fx or Sarvam', () async {
        final shared = path.join(home, '.agents');
        final catalog = AgentCatalog.create(
          platform: platform,
          detectionPort: FakeAgentDetectionPort(
            matches: (detection, _) => path.equals(detection.path, shared),
          ),
          builtIns: definitions(platform),
        ).valueOrNull!;
        expect(
          await catalog.detect(),
          isNot(contains(anyOf('deepseek-harness', 'fx', 'sarvam-code'))),
        );
      });
    });
  }
}
