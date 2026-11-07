import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/l10n/l10n.dart';

/// What one App version introduces, shown once after updating to it.
final class WhatsNewEntry {
  const WhatsNewEntry({
    required this.version,
    required this.heroAsset,
    required this.title,
    required this.body,
    this.darkHeroAsset,
    this.settingsSection,
    this.settingsAction,
  }) : assert((settingsSection == null) == (settingsAction == null));

  /// The `major.minor.patch` release that introduces it.
  final String version;

  /// A 480 × 216 image, exported at 2×.
  final String heroAsset;

  /// The same image on a dark background, for the dark appearance. The
  /// light one is used in both appearances when this is null.
  final String? darkHeroAsset;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) body;

  /// The Settings section the dialog offers a way into, labeled by
  /// [settingsAction].
  final SettingsSection? settingsSection;
  final String Function(AppLocalizations l10n)? settingsAction;
}

/// Newest last. Add an entry when a release has something worth announcing.
final whatsNewCatalog = <WhatsNewEntry>[
  WhatsNewEntry(
    version: '1.1.0',
    heroAsset: 'assets/whats_new/command_line.png',
    title: (l10n) => l10n.whatsNewCommandLineTitle,
    body: (l10n) => l10n.whatsNewCommandLineBody,
    settingsSection: SettingsSection.commandLine,
    settingsAction: (l10n) => l10n.whatsNewOpenCommandLineSettings,
  ),
  WhatsNewEntry(
    version: '1.1.4',
    heroAsset: 'assets/whats_new/dark_mode.png',
    darkHeroAsset: 'assets/whats_new/dark_mode_dark.png',
    title: (l10n) => l10n.whatsNewDarkModeTitle,
    body: (l10n) => l10n.whatsNewDarkModeBody,
    settingsSection: SettingsSection.appearance,
    settingsAction: (l10n) => l10n.whatsNewOpenAppearanceSettings,
  ),
];

/// The entry to show at launch, or null. It is resolved before `runApp`.
final pendingWhatsNewProvider = Provider<WhatsNewEntry?>((ref) => null);

/// Compares the numeric `major.minor.patch` core of two versions, ignoring
/// any pre-release or build suffix, so `1.0.9-20` and `1.0.9+20` equal `1.0.9`.
int compareAppVersions(String a, String b) {
  final left = _core(a);
  final right = _core(b);
  for (var i = 0; i < 3; i++) {
    final order = left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return 0;
}

List<int> _core(String version) {
  final core = version.trim().split(RegExp('[-+]')).first.split('.');
  return [
    for (var i = 0; i < 3; i++)
      i < core.length ? int.tryParse(core[i]) ?? 0 : 0,
  ];
}

/// The newest entry released after [lastSeen] and no later than [current].
/// A null [lastSeen] is a fresh install, which is never shown anything.
WhatsNewEntry? whatsNewFor({
  required String? lastSeen,
  required String current,
  List<WhatsNewEntry>? catalog,
}) {
  if (lastSeen == null) return null;
  WhatsNewEntry? newest;
  for (final entry in catalog ?? whatsNewCatalog) {
    if (compareAppVersions(entry.version, lastSeen) <= 0) continue;
    if (compareAppVersions(entry.version, current) > 0) continue;
    if (newest == null ||
        compareAppVersions(entry.version, newest.version) > 0) {
      newest = entry;
    }
  }
  return newest;
}
