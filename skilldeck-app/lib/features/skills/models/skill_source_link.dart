import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// A safe display label and the original address for explicit copying.
final class SkillSourceLink {
  const SkillSourceLink._({required this.label, this.copyText});

  final String label;

  /// Trimmed only at its edges. Never include this value in UI or diagnostics.
  final String? copyText;

  static SkillSourceLink fromSource(SkillSourceProvenance? source) {
    final locator = source?.locator.trim() ?? '';
    if (locator.isEmpty) return const SkillSourceLink._(label: '');
    SkillSourceLink value(String label) =>
        SkillSourceLink._(label: label, copyText: locator);
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(locator)) return value('');

    final local =
        source!.kind == WorkspaceSourceKind.local ||
        source.kind == WorkspaceSourceKind.adoptedSnapshot;
    // Local paths and adoption locators are not required to be valid web URLs.
    if (local && !locator.contains('://')) {
      return value(locator);
    }
    final parsed = Uri.tryParse(locator);
    if (parsed != null && parsed.host.isNotEmpty) {
      final label = parsed
          .replace(userInfo: '')
          .toString()
          .split(RegExp(r'[?#]'))
          .first;
      return value(label);
    }
    if (local &&
        parsed?.scheme == 'file' &&
        !parsed!.hasQuery &&
        !parsed.hasFragment) {
      try {
        final path = parsed.toFilePath();
        if (!RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) return value(path);
      } on Object {
        // Malformed file addresses still support copying, with a generic label.
      }
    }
    final ssh = locator.contains('://')
        ? null
        : RegExp(r'^(?:[^@/\s]+@)?([\w.-]+):([^\s?#]+)').firstMatch(locator);
    return value(ssh == null ? '' : '${ssh[1]}:${ssh[2]}');
  }
}
