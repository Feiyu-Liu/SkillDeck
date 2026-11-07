// Portions derived from vercel-labs/skills (MIT), Copyright (c) 2026 Vercel, Inc. See THIRD_PARTY_NOTICES.md.
import 'package:path/path.dart' as path;

import '../../domain/public_models.dart';

const int builtInAgentCatalogVersion = 1;

/// Builds the 73 built-in Agent conventions without reading process state.
List<AgentDefinition> buildBuiltInAgentDefinitions({
  required DesktopPlatform platform,
  required Map<String, String> environment,
  Set<String> existingPaths = const <String>{},
}) {
  final home = _homeDirectory(environment);
  final config = environment['XDG_CONFIG_HOME']?.trim().isNotEmpty == true
      ? environment['XDG_CONFIG_HOME']!.trim()
      : path.join(home, '.config');
  final codexHome = _envHome(
    environment,
    'CODEX_HOME',
    path.join(home, '.codex'),
  );
  final claudeHome = _envHome(
    environment,
    'CLAUDE_CONFIG_DIR',
    path.join(home, '.claude'),
  );
  final vibeHome = _envHome(environment, 'VIBE_HOME', path.join(home, '.vibe'));
  final hermesHome = _envHome(
    environment,
    'HERMES_HOME',
    path.join(home, '.hermes'),
  );
  final autohandHome = _envHome(
    environment,
    'AUTOHAND_HOME',
    path.join(home, '.autohand'),
  );
  final openClawHome = _firstExisting(<String>[
    path.join(home, '.openclaw'),
    path.join(home, '.clawdbot'),
    path.join(home, '.moltbot'),
  ], existingPaths);
  final universalGlobalSkillsPath = path.join(home, '.agents', 'skills');

  AgentDefinition agent(
    String id,
    String displayName,
    String projectSkillsPath,
    String? globalSkillsPath, {
    List<String>? absoluteDetectionPaths,
    List<String> projectDetectionPaths = const <String>[],
    List<String> projectPackageDependencies = const <String>[],
    bool requireAllDetectionPaths = false,
  }) {
    final universal = projectSkillsPath == '.agents/skills';
    final canonicalGlobalSkillsPath = universal && globalSkillsPath != null
        ? universalGlobalSkillsPath
        : globalSkillsPath;
    final globalDiscoverySkillsPaths = <String>[
      if (universal &&
          globalSkillsPath != null &&
          path.normalize(globalSkillsPath) !=
              path.normalize(universalGlobalSkillsPath))
        globalSkillsPath,
    ];
    final detections = <AgentDetectionPath>[
      for (final detectionPath
          in absoluteDetectionPaths ??
              (globalSkillsPath == null
                  ? const <String>[]
                  : <String>[path.dirname(globalSkillsPath)]))
        AgentDetectionPath.absolute(detectionPath),
      for (final detectionPath in projectDetectionPaths)
        AgentDetectionPath.projectRelative(detectionPath),
      for (final dependency in projectPackageDependencies)
        AgentDetectionPath.projectPackageDependency(dependency),
    ];
    return AgentDefinition(
      id: id,
      displayName: displayName,
      platforms: <DesktopPlatform, AgentPlatformDefinition>{
        platform: AgentPlatformDefinition(
          globalSkillsPath: canonicalGlobalSkillsPath,
          projectSkillsPath: projectSkillsPath,
          globalDiscoverySkillsPaths: globalDiscoverySkillsPaths,
          detectionPaths: detections,
          requireAllDetectionPaths: requireAllDetectionPaths,
        ),
      },
    );
  }

  String h(String value) => path.join(home, value);
  String c(String value) => path.join(config, value);

  return List.unmodifiable(<AgentDefinition>[
    agent(
      'aider-desk',
      'AiderDesk',
      '.aider-desk/skills',
      h('.aider-desk/skills'),
    ),
    agent(
      'amp',
      'Amp',
      '.agents/skills',
      c('agents/skills'),
      absoluteDetectionPaths: <String>[c('amp')],
    ),
    agent(
      'antigravity',
      'Antigravity',
      '.agents/skills',
      h('.gemini/antigravity/skills'),
    ),
    agent(
      'antigravity-cli',
      'Antigravity CLI',
      '.agents/skills',
      h('.gemini/antigravity-cli/skills'),
    ),
    agent(
      'astrbot',
      'AstrBot',
      'data/skills',
      h('.astrbot/data/skills'),
      absoluteDetectionPaths: <String>[h('.astrbot')],
      projectDetectionPaths: const <String>['data/skills'],
    ),
    agent(
      'autohand-code',
      'Autohand Code CLI',
      '.autohand/skills',
      path.join(autohandHome, 'skills'),
    ),
    agent('augment', 'Augment', '.augment/skills', h('.augment/skills')),
    agent('bob', 'IBM Bob', '.bob/skills', h('.bob/skills')),
    agent(
      'claude-code',
      'Claude Code',
      '.claude/skills',
      path.join(claudeHome, 'skills'),
    ),
    agent(
      'openclaw',
      'OpenClaw',
      'skills',
      path.join(openClawHome, 'skills'),
      absoluteDetectionPaths: <String>[
        h('.openclaw'),
        h('.clawdbot'),
        h('.moltbot'),
      ],
    ),
    agent(
      'cline',
      'Cline',
      '.agents/skills',
      h('.agents/skills'),
      absoluteDetectionPaths: <String>[h('.cline')],
    ),
    agent(
      'codearts-agent',
      'CodeArts Agent',
      '.codeartsdoer/skills',
      h('.codeartsdoer/skills'),
    ),
    agent(
      'codebuddy',
      'CodeBuddy',
      '.codebuddy/skills',
      h('.codebuddy/skills'),
      absoluteDetectionPaths: <String>[h('.codebuddy')],
      projectDetectionPaths: const <String>['.codebuddy'],
    ),
    agent(
      'codemaker',
      'Codemaker',
      '.codemaker/skills',
      h('.codemaker/skills'),
    ),
    agent(
      'codestudio',
      'Code Studio',
      '.codestudio/skills',
      h('.codestudio/skills'),
    ),
    agent(
      'codex',
      'Codex',
      '.agents/skills',
      path.join(codexHome, 'skills'),
      absoluteDetectionPaths: <String>[codexHome, '/etc/codex'],
    ),
    agent(
      'command-code',
      'Command Code',
      '.commandcode/skills',
      h('.commandcode/skills'),
    ),
    agent(
      'continue',
      'Continue',
      '.continue/skills',
      h('.continue/skills'),
      absoluteDetectionPaths: <String>[h('.continue')],
      projectDetectionPaths: const <String>['.continue'],
    ),
    agent(
      'cortex',
      'Cortex Code',
      '.cortex/skills',
      h('.snowflake/cortex/skills'),
    ),
    agent('crush', 'Crush', '.crush/skills', c('crush/skills')),
    agent('cursor', 'Cursor', '.agents/skills', h('.cursor/skills')),
    agent(
      'deepagents',
      'Deep Agents',
      '.agents/skills',
      h('.deepagents/agent/skills'),
    ),
    agent('devin', 'Devin for Terminal', '.devin/skills', c('devin/skills')),
    agent(
      'dexto',
      'Dexto',
      '.agents/skills',
      h('.agents/skills'),
      absoluteDetectionPaths: <String>[h('.dexto')],
    ),
    agent('droid', 'Droid', '.factory/skills', h('.factory/skills')),
    agent(
      'eve',
      'Eve',
      'agent/skills',
      null,
      projectDetectionPaths: const <String>['agent'],
      projectPackageDependencies: const <String>['eve'],
      requireAllDetectionPaths: true,
    ),
    agent(
      'firebender',
      'Firebender',
      '.agents/skills',
      h('.firebender/skills'),
    ),
    agent('forgecode', 'ForgeCode', '.forge/skills', h('.forge/skills')),
    agent('gemini-cli', 'Gemini CLI', '.agents/skills', h('.gemini/skills')),
    agent(
      'github-copilot',
      'GitHub Copilot',
      '.agents/skills',
      h('.copilot/skills'),
    ),
    agent('goose', 'Goose', '.goose/skills', c('goose/skills')),
    agent(
      'hermes-agent',
      'Hermes Agent',
      '.hermes/skills',
      path.join(hermesHome, 'skills'),
    ),
    agent(
      'inference-sh',
      'inference.sh',
      '.inferencesh/skills',
      h('.inferencesh/skills'),
    ),
    agent(
      'jazz',
      'Jazz',
      '.jazz/skills',
      h('.jazz/skills'),
      absoluteDetectionPaths: <String>[h('.jazz')],
      projectDetectionPaths: const <String>['.jazz'],
    ),
    agent('junie', 'Junie', '.junie/skills', h('.junie/skills')),
    agent('iflow-cli', 'iFlow CLI', '.iflow/skills', h('.iflow/skills')),
    agent('kilo', 'Kilo Code', '.kilocode/skills', h('.kilocode/skills')),
    agent(
      'kimi-code-cli',
      'Kimi Code CLI',
      '.agents/skills',
      h('.agents/skills'),
      absoluteDetectionPaths: <String>[h('.kimi-code'), h('.kimi')],
    ),
    agent('kiro-cli', 'Kiro CLI', '.kiro/skills', h('.kiro/skills')),
    agent('kode', 'Kode', '.kode/skills', h('.kode/skills')),
    agent('lingma', 'Lingma', '.lingma/skills', h('.lingma/skills')),
    agent(
      'loaf',
      'Loaf',
      '.agents/skills',
      h('.agents/skills'),
      absoluteDetectionPaths: <String>[h('.loaf')],
    ),
    agent('mcpjam', 'MCPJam', '.mcpjam/skills', h('.mcpjam/skills')),
    agent(
      'mistral-vibe',
      'Mistral Vibe',
      '.vibe/skills',
      path.join(vibeHome, 'skills'),
    ),
    agent('moxby', 'Moxby', '.moxby/skills', h('.moxby/skills')),
    agent('mux', 'Mux', '.mux/skills', h('.mux/skills')),
    agent('opencode', 'OpenCode', '.agents/skills', c('opencode/skills')),
    agent(
      'openhands',
      'OpenHands',
      '.openhands/skills',
      h('.openhands/skills'),
    ),
    agent('ona', 'Ona', '.ona/skills', h('.ona/skills')),
    agent('pi', 'Pi', '.pi/skills', h('.pi/agent/skills')),
    agent('qoder', 'Qoder', '.qoder/skills', h('.qoder/skills')),
    agent('qoder-cn', 'Qoder CN', '.qoder/skills', h('.qoder-cn/skills')),
    agent('qwen-code', 'Qwen Code', '.qwen/skills', h('.qwen/skills')),
    agent(
      'replit',
      'Replit',
      '.agents/skills',
      c('agents/skills'),
      absoluteDetectionPaths: const <String>[],
      projectDetectionPaths: const <String>['.replit'],
    ),
    agent('reasonix', 'Reasonix', '.reasonix/skills', h('.reasonix/skills')),
    agent('rovodev', 'Rovo Dev', '.rovodev/skills', h('.rovodev/skills')),
    agent('roo', 'Roo Code', '.roo/skills', h('.roo/skills')),
    agent(
      'tabnine-cli',
      'Tabnine CLI',
      '.tabnine/agent/skills',
      h('.tabnine/agent/skills'),
    ),
    agent(
      'terramind',
      'Terramind',
      '.terramind/skills',
      h('.terramind/skills'),
    ),
    agent(
      'tinycloud',
      'Tinycloud',
      '.tinycloud/skills',
      h('.tinycloud/skills'),
    ),
    agent('trae', 'Trae', '.trae/skills', h('.trae/skills')),
    agent('trae-cn', 'Trae CN', '.trae/skills', h('.trae-cn/skills')),
    agent(
      'warp',
      'Warp',
      '.agents/skills',
      h('.agents/skills'),
      absoluteDetectionPaths: <String>[h('.warp')],
    ),
    agent(
      'windsurf',
      'Windsurf',
      '.windsurf/skills',
      h('.codeium/windsurf/skills'),
    ),
    agent(
      'zed',
      'Zed',
      '.agents/skills',
      h('.agents/skills'),
      absoluteDetectionPaths: <String>[
        c('zed'),
        if (environment['APPDATA']?.trim().isNotEmpty == true)
          path.join(environment['APPDATA']!.trim(), 'Zed'),
        if (environment['FLATPAK_XDG_CONFIG_HOME']?.trim().isNotEmpty == true)
          path.join(environment['FLATPAK_XDG_CONFIG_HOME']!.trim(), 'zed'),
      ],
    ),
    agent(
      'zcode',
      'ZCode',
      '.zcode/skills',
      h('.zcode/skills'),
      absoluteDetectionPaths: <String>[h('.zcode'), '/Applications/ZCode.app'],
    ),
    agent('zencoder', 'Zencoder', '.zencoder/skills', h('.zencoder/skills')),
    agent('zenflow', 'Zenflow', '.zencoder/skills', h('.zencoder/skills')),
    agent('neovate', 'Neovate', '.neovate/skills', h('.neovate/skills')),
    agent('pochi', 'Pochi', '.pochi/skills', h('.pochi/skills')),
    agent(
      'promptscript',
      'PromptScript',
      '.agents/skills',
      null,
      projectDetectionPaths: const <String>[
        '.promptscript',
        'promptscript.yaml',
      ],
    ),
    agent('adal', 'AdaL', '.adal/skills', h('.adal/skills')),
    agent(
      'universal',
      'Universal',
      '.agents/skills',
      c('agents/skills'),
      absoluteDetectionPaths: const <String>[],
    ),
  ]);
}

String _homeDirectory(Map<String, String> environment) {
  final home = environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return home;
  }
  final profile = environment['USERPROFILE']?.trim();
  if (profile != null && profile.isNotEmpty) {
    return profile;
  }
  throw StateError('A home directory is required to build the Agent Catalog.');
}

String _envHome(Map<String, String> environment, String key, String fallback) {
  final value = environment[key]?.trim();
  return value == null || value.isEmpty ? fallback : value;
}

String _firstExisting(List<String> candidates, Set<String> existingPaths) {
  final normalized = existingPaths.map(path.normalize).toSet();
  return candidates.firstWhere(
    (candidate) => normalized.contains(path.normalize(candidate)),
    orElse: () => candidates.first,
  );
}
