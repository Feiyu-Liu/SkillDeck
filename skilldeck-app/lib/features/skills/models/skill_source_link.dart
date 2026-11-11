import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// A display address and an optional browser target derived only from provenance.
final class SkillSourceLink {
  const SkillSourceLink._({required this.label, this.uri});

  final String label;
  final Uri? uri;

  static SkillSourceLink fromSource(SkillSourceProvenance? source) {
    if (source == null) return const SkillSourceLink._(label: '');
    final locator = source.locator.trim();
    final parsed = Uri.tryParse(locator);
    if (source.kind == WorkspaceSourceKind.local &&
        (parsed == null || !parsed.hasAuthority)) {
      return SkillSourceLink._(label: locator);
    }
    if (RegExp(r'[\x00-\x20\x7f\\]').hasMatch(locator)) {
      return const SkillSourceLink._(label: '');
    }
    if (parsed == null || parsed.host.isEmpty) {
      // SCP-style Git locators have no web URL. Remove their SSH user, too.
      final ssh = RegExp(r'^(?:[^@/\s]+@)?([\w.-]+):([^\s?#]+)$')
          .firstMatch(locator);
      return SkillSourceLink._(label: ssh == null ? '' : '${ssh[1]}:${ssh[2]}');
    }

    // This is not a generic token detector. Only GitHub's fixed README UI
    // locator is recognized; every other query or fragment is hidden and makes
    // the original locator ineligible for opening. Never open a rewritten URL.
    final githubRepository =
        source.kind == WorkspaceSourceKind.git &&
        parsed.host == 'github.com' &&
        parsed.pathSegments.length == 2;
    final safeQuery =
        !parsed.hasQuery ||
        (githubRepository && parsed.query == 'tab=readme-ov-file');
    final safeFragment =
        !parsed.hasFragment ||
        (githubRepository && parsed.fragment == 'readme');
    final safe = parsed.replace(
      userInfo: '',
      query: safeQuery ? null : '',
      fragment: safeFragment ? null : '',
    );
    final web =
        source.kind != WorkspaceSourceKind.local &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.userInfo.isEmpty &&
        safeQuery &&
        safeFragment;
    return SkillSourceLink._(label: safe.toString(), uri: web ? parsed : null);
  }
}
