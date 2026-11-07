import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';

final class SkillSourceLocatorResolver {
  SkillSourceLocatorResolver({String? homePath})
    : _homePath = homePath ?? Platform.environment['HOME'];

  final String? _homePath;

  ResolvedSkillSource resolve(SkillSourceDraft draft) {
    final value = switch (draft.kind) {
      SkillSourceKind.local => normalizeLocalLocatorInput(draft.locator),
      SkillSourceKind.git => normalizeGitLocatorInput(draft.locator),
      SkillSourceKind.wellKnown => draft.locator.trim(),
    };
    if (value.isEmpty) {
      throw const SkillAcquisitionException(
        operation: SkillAcquisitionOperation.resolveSource,
        code: SkillAcquisitionErrorCode.emptyLocator,
      );
    }

    return switch (draft.kind) {
      SkillSourceKind.local => _resolveLocal(value),
      SkillSourceKind.git => ResolvedSkillSource(
        kind: SkillSourceKind.git,
        value: value,
        ref: draft.sourceRef.trim().isEmpty ? null : draft.sourceRef.trim(),
        repositorySubpath: normalizeRepositorySubpathInput(
          draft.repositorySubpath,
        ),
      ),
      SkillSourceKind.wellKnown => ResolvedSkillSource(
        kind: SkillSourceKind.wellKnown,
        value: value,
      ),
    };
  }

  ResolvedSkillSource _resolveLocal(String value) {
    final uri = Uri.tryParse(value);
    final path = uri?.scheme.toLowerCase() == 'file'
        ? _fileUriPath(uri!)
        : _expandHome(value);
    if (!p.isAbsolute(path) || p.isRootRelative(path)) {
      throw const SkillAcquisitionException(
        operation: SkillAcquisitionOperation.resolveSource,
        code: SkillAcquisitionErrorCode.invalidLocalLocator,
      );
    }
    return ResolvedSkillSource(
      kind: SkillSourceKind.local,
      value: p.normalize(path),
    );
  }

  String _fileUriPath(Uri uri) {
    try {
      return uri.toFilePath();
    } on Object {
      throw const SkillAcquisitionException(
        operation: SkillAcquisitionOperation.resolveSource,
        code: SkillAcquisitionErrorCode.invalidFileLocator,
      );
    }
  }

  /// Cleans the shapes people paste for a Git Source into the locator the
  /// Workspace parses.
  ///
  /// The Workspace keeps its own safety rules: it still rejects queries,
  /// userinfo, and unsupported transports. This only strips what a browser or
  /// a README adds around an otherwise valid locator, so a copied install
  /// command or address bar works on the first try.
  static String normalizeGitLocatorInput(String input) {
    var value = input.trim();
    final arguments = installCommandArguments(value);
    if (arguments != null) {
      // `npx skills add owner/repo --skill name`: keep only the Source. The
      // selection step offers the Skills the command's flags would pick.
      value = arguments.trim().split(_whitespace).first;
    }
    final selection = value.lastIndexOf('@');
    if (selection > 0) {
      final source = value.substring(0, selection);
      final skill = value.substring(selection + 1);
      if (skill.isNotEmpty &&
          !skill.contains('/') &&
          !skill.contains('#') &&
          (source.contains('#') || _gitShorthand.hasMatch(source))) {
        value = source;
      }
    }
    if (_schemelessWebHost.hasMatch(value)) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'https' &&
        _webHosts.contains(uri.host.toLowerCase())) {
      final fragment = uri.hasFragment ? uri.fragment : null;
      final keepFragment =
          fragment != null && !_pageAnchors.contains(fragment.toLowerCase());
      // Queries and page anchors are page state, never part of the
      // repository: GitHub adds `?tab=readme-ov-file` and `#readme`.
      // Userinfo is kept on purpose so the Workspace still rejects it rather
      // than this silently dropping a credential the user pasted.
      value = Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
        fragment: keepFragment ? fragment : null,
      ).toString();
    }
    return value;
  }

  static String? installCommandArguments(String input) {
    final command = _skillsCliAddCommand.firstMatch(input);
    return command == null ? null : input.substring(command.end);
  }

  /// Turns a typed repository subpath into the relative form the Workspace
  /// accepts: forward slashes, no leading `./` or `/`, no trailing `/`.
  static String normalizeRepositorySubpathInput(String input) {
    var value = input.trim().replaceAll(r'\', '/');
    while (value.startsWith('./')) {
      value = value.substring(2);
    }
    return value.replaceAll(RegExp(r'^/+|/+$'), '');
  }

  /// Removes the quotes that Windows Explorer's "Copy as path" puts around a
  /// folder path.
  static String normalizeLocalLocatorInput(String input) {
    final value = input.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  static final _skillsCliAddCommand = RegExp(
    r'^(?:npx|pnpx|bunx|pnpm\s+dlx|yarn\s+dlx)\s+(?:(?:-y|--yes)\s+)?skills(?:@\S+)?\s+(?:add|a|install|i)\s+',
    caseSensitive: false,
  );
  static final _gitShorthand = RegExp(
    r'^[^./:@#\s][^/:@#\s]*/[^/:@#\s]+(?:/[^/:@#\s]+)*$',
  );
  static final _whitespace = RegExp(r'\s+');
  static final _schemelessWebHost = RegExp(
    r'^(?:www\.)?(?:github\.com|gitlab\.com)/',
    caseSensitive: false,
  );
  static const _webHosts = {'github.com', 'www.github.com', 'gitlab.com'};
  static const _pageAnchors = {'readme', 'readme-ov-file'};

  String _expandHome(String value) {
    if (value == '~' || value.startsWith('~/')) {
      final home = _homePath;
      if (home == null || home.trim().isEmpty) return value;
      return value == '~' ? home : p.join(home, value.substring(2));
    }
    return value;
  }
}
