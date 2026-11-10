import 'dart:convert';

import 'package:skills_manager/features/skills/models/skills_workspace.dart';

enum AppLocalePreference { system, zh, en }

/// Desktop platforms supported by App-owned Custom Agent settings.
///
/// This is intentionally independent from the Workspace package so persisted
/// UI settings do not expose a backend domain type.
enum AppDesktopPlatform { macos, windows, linux }

final class CustomAgentPlatformSettings {
  const CustomAgentPlatformSettings({
    this.globalSkillsPath,
    this.projectSkillsPath,
    this.globalDiscoverySkillsPaths = const <String>[],
    this.projectDiscoverySkillsPaths = const <String>[],
  });

  final String? globalSkillsPath;
  final String? projectSkillsPath;
  final List<String> globalDiscoverySkillsPaths;
  final List<String> projectDiscoverySkillsPaths;

  void validate() {
    if (globalSkillsPath != null && !_isAbsolutePath(globalSkillsPath!)) {
      throw const FormatException('Global skills path must be absolute.');
    }
    if (projectSkillsPath != null && !_isSafeRelativePath(projectSkillsPath!)) {
      throw const FormatException('Project skills path must be relative.');
    }
    if (globalSkillsPath == null && globalDiscoverySkillsPaths.isNotEmpty) {
      throw const FormatException(
        'Global discovery paths require a global skills path.',
      );
    }
    if (projectSkillsPath == null && projectDiscoverySkillsPaths.isNotEmpty) {
      throw const FormatException(
        'Project discovery paths require a project skills path.',
      );
    }
    for (final discoveryPath in globalDiscoverySkillsPaths) {
      if (!_isAbsolutePath(discoveryPath)) {
        throw const FormatException('Global discovery paths must be absolute.');
      }
    }
    for (final discoveryPath in projectDiscoverySkillsPaths) {
      if (!_isSafeRelativePath(discoveryPath)) {
        throw const FormatException(
          'Project discovery paths must be relative.',
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    if (globalSkillsPath != null) 'globalSkillsPath': globalSkillsPath,
    if (projectSkillsPath != null) 'projectSkillsPath': projectSkillsPath,
    if (globalDiscoverySkillsPaths.isNotEmpty)
      'globalDiscoverySkillsPaths': globalDiscoverySkillsPaths,
    if (projectDiscoverySkillsPaths.isNotEmpty)
      'projectDiscoverySkillsPaths': projectDiscoverySkillsPaths,
  };

  factory CustomAgentPlatformSettings.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Agent platform must be an object.');
    }
    final json = Map<String, Object?>.from(value);
    final settings = CustomAgentPlatformSettings(
      globalSkillsPath: _nullableString(json['globalSkillsPath']),
      projectSkillsPath: _nullableString(json['projectSkillsPath']),
      globalDiscoverySkillsPaths: _stringList(
        json['globalDiscoverySkillsPaths'],
      ),
      projectDiscoverySkillsPaths: _stringList(
        json['projectDiscoverySkillsPaths'],
      ),
    );
    if (settings.isEmpty) {
      throw const FormatException('Agent platform needs a skill path.');
    }
    settings.validate();
    return settings;
  }

  bool get isEmpty => globalSkillsPath == null && projectSkillsPath == null;
}

final class CustomAgentSettings {
  const CustomAgentSettings({
    required this.id,
    required this.displayName,
    required this.iconName,
    required this.platforms,
  });

  final String id;
  final String displayName;
  final String iconName;
  final Map<AppDesktopPlatform, CustomAgentPlatformSettings> platforms;

  void validate() {
    if (id.trim().isEmpty ||
        !id.startsWith('custom-') ||
        displayName.trim().isEmpty ||
        iconName.trim().isEmpty) {
      throw const FormatException('Custom Agent fields must not be empty.');
    }
    if (platforms.isEmpty) {
      throw const FormatException('Custom Agent needs a platform path.');
    }
    for (final settings in platforms.values) {
      if (settings.isEmpty) {
        throw const FormatException('Agent platform needs a skill path.');
      }
      settings.validate();
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'iconName': iconName,
    'platforms': {
      for (final entry in platforms.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  factory CustomAgentSettings.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Custom Agent must be an object.');
    }
    final json = Map<String, Object?>.from(value);
    final platformsValue = json['platforms'];
    if (platformsValue is! Map) {
      throw const FormatException('Custom Agent platforms must be an object.');
    }
    final platforms = <AppDesktopPlatform, CustomAgentPlatformSettings>{};
    for (final entry in platformsValue.entries) {
      final platform = AppDesktopPlatform.values
          .where((item) => item.name == entry.key)
          .firstOrNull;
      if (platform == null) {
        throw const FormatException('Unknown Agent platform.');
      }
      final settings = CustomAgentPlatformSettings.fromJson(entry.value);
      if (!settings.isEmpty) platforms[platform] = settings;
    }
    final id = _requiredString(json['id']);
    final displayName = _requiredString(json['displayName']);
    final iconName = _requiredString(json['iconName']);
    final agent = CustomAgentSettings(
      id: id,
      displayName: displayName,
      iconName: iconName,
      platforms: Map.unmodifiable(platforms),
    );
    agent.validate();
    return agent;
  }
}

final class AppSettings {
  const AppSettings({
    this.version = currentVersion,
    this.localePreference = AppLocalePreference.system,
    this.suppressDuplicateActivationConfirmation = false,
    this.sidebarCollapsed = false,
    this.customAgents = const [],
    this.builtInAgentVisibilityOverrides = const {},
    this.globalActivationMethod = WorkspaceActivationMethod.automatic,
  });

  static const currentVersion = 1;

  final int version;
  final AppLocalePreference localePreference;
  final bool suppressDuplicateActivationConfirmation;
  final bool sidebarCollapsed;
  final List<CustomAgentSettings> customAgents;
  final Map<String, bool> builtInAgentVisibilityOverrides;

  /// How new global Activations are materialized. Project Activations always
  /// copy, so this preference never applies to them.
  final WorkspaceActivationMethod globalActivationMethod;

  void validate() {
    if (version != currentVersion) {
      throw const FormatException('Unsupported app settings version.');
    }
    final ids = <String>{};
    for (final agent in customAgents) {
      agent.validate();
      if (!ids.add(agent.id)) {
        throw const FormatException('Custom Agent IDs must be unique.');
      }
    }
    for (final id in builtInAgentVisibilityOverrides.keys) {
      if (id.trim().isEmpty || id == 'universal' || id.startsWith('custom-')) {
        throw const FormatException('Invalid built-in Agent membership.');
      }
    }
  }

  AppSettings copyWith({
    AppLocalePreference? localePreference,
    bool? suppressDuplicateActivationConfirmation,
    bool? sidebarCollapsed,
    List<CustomAgentSettings>? customAgents,
    Map<String, bool>? builtInAgentVisibilityOverrides,
    WorkspaceActivationMethod? globalActivationMethod,
  }) => AppSettings(
    version: currentVersion,
    localePreference: localePreference ?? this.localePreference,
    suppressDuplicateActivationConfirmation:
        suppressDuplicateActivationConfirmation ??
        this.suppressDuplicateActivationConfirmation,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    customAgents: customAgents ?? this.customAgents,
    builtInAgentVisibilityOverrides: Map.unmodifiable(
      builtInAgentVisibilityOverrides ?? this.builtInAgentVisibilityOverrides,
    ),
    globalActivationMethod:
        globalActivationMethod ?? this.globalActivationMethod,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'localePreference': localePreference.name,
    'suppressDuplicateActivationConfirmation':
        suppressDuplicateActivationConfirmation,
    'sidebarCollapsed': sidebarCollapsed,
    'customAgents': [for (final agent in customAgents) agent.toJson()],
    'builtInAgentVisibilityOverrides': builtInAgentVisibilityOverrides,
    'globalActivationMethod': globalActivationMethod.name,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    if (json['version'] != currentVersion) {
      throw const FormatException('Unsupported app settings version.');
    }
    final localeRaw = json['localePreference'];
    final locale = AppLocalePreference.values
        .where((item) => item.name == localeRaw)
        .firstOrNull;
    if (locale == null) {
      throw const FormatException('Unknown app locale preference.');
    }
    final suppressDuplicateActivationConfirmation =
        json['suppressDuplicateActivationConfirmation'] ?? false;
    if (suppressDuplicateActivationConfirmation is! bool) {
      throw const FormatException(
        'suppressDuplicateActivationConfirmation must be a boolean.',
      );
    }
    final sidebarCollapsed = json['sidebarCollapsed'] ?? false;
    if (sidebarCollapsed is! bool) {
      throw const FormatException('sidebarCollapsed must be a boolean.');
    }
    final agentsRaw = json['customAgents'];
    if (agentsRaw is! List) {
      throw const FormatException('customAgents must be an array.');
    }
    final agents = [
      for (final value in agentsRaw) CustomAgentSettings.fromJson(value),
    ];
    final overrides =
        json['builtInAgentVisibilityOverrides'] ?? const <String, bool>{};
    if (overrides is! Map ||
        overrides.entries.any(
          (entry) =>
              entry.key is! String ||
              (entry.key as String).isEmpty ||
              entry.value is! bool,
        )) {
      throw const FormatException('Invalid built-in Agent membership.');
    }
    final methodRaw =
        json['globalActivationMethod'] ??
        WorkspaceActivationMethod.automatic.name;
    final method = WorkspaceActivationMethod.values
        .where((item) => item.name == methodRaw)
        .firstOrNull;
    if (method == null) {
      throw const FormatException('Unknown global activation method.');
    }
    final settings = AppSettings(
      localePreference: locale,
      suppressDuplicateActivationConfirmation:
          suppressDuplicateActivationConfirmation,
      sidebarCollapsed: sidebarCollapsed,
      customAgents: List.unmodifiable(agents),
      builtInAgentVisibilityOverrides: Map.unmodifiable(
        Map<String, bool>.from(overrides),
      ),
      globalActivationMethod: method,
    );
    settings.validate();
    return settings;
  }

  static AppSettings decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('App settings must be an object.');
    }
    return AppSettings.fromJson(Map<String, Object?>.from(decoded));
  }
}

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('A required string is missing.');
  }
  return value.trim();
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('A path must be a non-empty string.');
  }
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List) {
    throw const FormatException('A path list must be an array.');
  }
  final paths = <String>[];
  for (final item in value) {
    final path = _nullableString(item);
    if (path == null) {
      throw const FormatException('A path must be a non-empty string.');
    }
    paths.add(path);
  }
  return List.unmodifiable(paths);
}

bool _isAbsolutePath(String value) {
  final normalized = value.trim();
  return normalized.startsWith('/') ||
      normalized.startsWith(r'\\') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(normalized);
}

bool _isSafeRelativePath(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.startsWith(r'\\') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(normalized)) {
    return false;
  }
  return !normalized.split(RegExp(r'[\\/]')).contains('..');
}
