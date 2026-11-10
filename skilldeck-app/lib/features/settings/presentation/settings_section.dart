enum SettingsSection {
  appearance('appearance'),
  general('general'),
  agents('agents'),
  translation('translation'),
  commandLine('command-line'),
  maintenance('maintenance'),
  about('about');

  const SettingsSection(this.id);

  final String id;
}

/// Section ids from earlier releases, kept so saved links and deep links into
/// a section that was merged into another one still land on its content.
const _legacySectionIds = {
  'project-roots': SettingsSection.general,
  'language': SettingsSection.general,
  'custom-agents': SettingsSection.agents,
  'workspace-validation': SettingsSection.maintenance,
  'environment': SettingsSection.maintenance,
  'updates': SettingsSection.about,
};

SettingsSection? parseSettingsSection(String? value) {
  if (_legacySectionIds[value] case final section?) return section;
  for (final section in SettingsSection.values) {
    if (section.id == value) return section;
  }
  return null;
}

String settingsLocation(SettingsSection? section) {
  if (section == null) return '/settings';
  return '/settings?section=${section.id}';
}
