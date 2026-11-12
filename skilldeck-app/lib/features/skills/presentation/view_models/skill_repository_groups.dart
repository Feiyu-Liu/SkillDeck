import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

enum SkillRepositoryBucket { repository, local, web, unknown }

/// Safe display identity only. Never used as a Source or Workspace identity.
final class SkillRepositoryIdentity {
  const SkillRepositoryIdentity({
    required this.key,
    required this.title,
    this.host = '',
    this.tooltip,
    this.bucket = SkillRepositoryBucket.repository,
  });

  final String key;
  final String title;
  final String host;
  final String? tooltip;
  final SkillRepositoryBucket bucket;
}

final class SkillRepositoryGroup {
  SkillRepositoryGroup(this.identity, Iterable<InstalledSkill> skills)
    : skills = List.unmodifiable(skills);

  final SkillRepositoryIdentity identity;
  final List<InstalledSkill> skills;
}

/// Projects the already filtered and sorted members; their original order and
/// objects survive grouping. Recomputed from current provenance on every call.
List<SkillRepositoryGroup> groupSkillsByRepository(
  Iterable<InstalledSkill> skills,
) {
  final identities = <String, SkillRepositoryIdentity>{};
  final members = <String, List<InstalledSkill>>{};
  for (final skill in skills) {
    final identity = repositoryIdentity(skill.source);
    identities[identity.key] = identity;
    (members[identity.key] ??= []).add(skill);
  }
  final groups =
      [
        for (final entry in members.entries)
          SkillRepositoryGroup(identities[entry.key]!, entry.value),
      ]..sort((left, right) {
        final a = left.identity;
        final b = right.identity;
        var result = a.bucket.index.compareTo(b.bucket.index);
        if (result == 0) {
          result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        if (result == 0) result = a.host.compareTo(b.host);
        return result == 0 ? a.key.compareTo(b.key) : result;
      });
  return List.unmodifiable(groups);
}

const _unknown = SkillRepositoryIdentity(
  key: 'fallback:unknown',
  title: '',
  bucket: SkillRepositoryBucket.unknown,
);

SkillRepositoryIdentity repositoryIdentity(SkillSourceProvenance? source) {
  if (source == null || source.locator.trim().isEmpty) return _unknown;
  switch (source.kind) {
    case WorkspaceSourceKind.local:
    case WorkspaceSourceKind.adoptedSnapshot:
      return const SkillRepositoryIdentity(
        key: 'fallback:local',
        title: '',
        bucket: SkillRepositoryBucket.local,
      );
    case WorkspaceSourceKind.wellKnown:
      return const SkillRepositoryIdentity(
        key: 'fallback:web',
        title: '',
        bucket: SkillRepositoryBucket.web,
      );
    case WorkspaceSourceKind.git:
      return _gitIdentity(source.locator) ?? _unknown;
  }
}

SkillRepositoryIdentity? _gitIdentity(String locator) {
  // This is a display projection of provenance, never an install parser.
  if (locator.isEmpty ||
      locator != locator.trim() ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(locator)) {
    return null;
  }
  try {
    var value = locator;
    final windowsPath = RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)').hasMatch(value);
    if (windowsPath || value.startsWith('/')) {
      return _localIdentity(value, windows: windowsPath);
    }
    if (value.startsWith('file:')) {
      final uri = Uri.parse(value);
      if (uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.host.isNotEmpty && uri.host != 'localhost')) {
        return null;
      }
      final windowsFile = RegExp(r'^/[a-zA-Z]:/').hasMatch(uri.path);
      return _localIdentity(
        uri.replace(host: '').toFilePath(windows: windowsFile),
        windows: windowsFile,
      );
    }
    if (RegExp(r'[\s?#]').hasMatch(value)) return null;
    if (!value.contains('://')) {
      // A malformed SCP username must never be reinterpreted as a repository
      // path (user:password@host:path). Only the conventional username form
      // may precede the one optional @.
      final decoded = Uri.decodeComponent(value);
      if (decoded.contains('@')) {
        final at = decoded.indexOf('@');
        if (at != decoded.lastIndexOf('@') ||
            !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(decoded.substring(0, at))) {
          return null;
        }
      }
      final scp = RegExp(r'^(?:([^@/:]+)@)?(\[[^\]]+\]|[^/:]+):(.+)$')
          .firstMatch(value);
      if (scp == null) return null;
      value = 'ssh://${scp[2]}/${scp[3]}';
    }
    // Uri normalizes dot segments, so validate the original path first.
    final pathStart = value.indexOf('/', value.indexOf('://') + 3);
    if (pathStart < 0) return null;
    final rawPath = value
        .substring(pathStart + 1)
        .replaceAll(RegExp(r'/+$'), '');
    final segments = rawPath.split('/').map(Uri.decodeComponent).toList();
    if (segments.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(part),
    )) {
      return null;
    }
    final uri = Uri.parse(value);
    final scheme = uri.scheme.toLowerCase();
    if (!const {'https', 'http', 'ssh', 'git'}.contains(scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.userInfo.isNotEmpty &&
            (scheme != 'ssh' ||
                !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(uri.userInfo))) ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (RegExp(r'[\s/@?#\\]').hasMatch(host) ||
        host.startsWith('.') ||
        host.endsWith('.') ||
        host.contains('..')) {
      return null;
    }
    var path = segments.join('/');
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    if (path.isEmpty || path.endsWith('/')) return null;
    if (host == 'github.com') path = path.toLowerCase();
    final defaultPort = switch (scheme) {
      'https' => 443,
      'http' => 80,
      'ssh' => 22,
      _ => 9418,
    };
    final displayHost = host.contains(':') && !host.startsWith('[')
        ? '[$host]'
        : host;
    final authority = uri.hasPort && uri.port != defaultPort
        ? '$displayHost:${uri.port}'
        : displayHost;
    return SkillRepositoryIdentity(
      key: 'git:remote:$authority/$path',
      title: path,
      host: authority,
      tooltip: '$authority/$path',
    );
  } on Object {
    return null;
  }
}

SkillRepositoryIdentity? _localIdentity(String value, {bool windows = false}) {
  if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) return null;
  final context = p.Context(style: windows ? p.Style.windows : p.Style.posix);
  if (!context.isAbsolute(value) || context.isRootRelative(value)) return null;
  final path = context.normalize(value);
  final title = context.basename(path);
  if (title.isEmpty || title == context.separator) return null;
  return SkillRepositoryIdentity(
    key: 'git:local:$path',
    title: title,
    tooltip: path,
  );
}
