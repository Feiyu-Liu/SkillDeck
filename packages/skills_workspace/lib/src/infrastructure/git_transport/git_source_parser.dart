// Portions derived from vercel-labs/skills (MIT), Copyright (c) 2026 Vercel, Inc. See THIRD_PARTY_NOTICES.md.
import '../../domain/source_descriptor.dart';
import 'git_transport_result.dart';

final class ParsedGitSource {
  const ParsedGitSource({required this.descriptor, this.skillFilter});

  final GitSourceDescriptor descriptor;
  final String? skillFilter;
}

final class GitSourceParser {
  const GitSourceParser();

  GitTransportResult<GitSourceDescriptor> parse(String input) {
    final parsed = parseWithSelection(input);
    final value = parsed.valueOrNull;
    if (value != null) {
      return GitTransportSuccess(value.descriptor);
    }
    return _copyFailure<ParsedGitSource, GitSourceDescriptor>(
      parsed.failureOrNull!,
    );
  }

  GitTransportResult<ParsedGitSource> parseWithSelection(String input) {
    final selection = _splitSkillSelection(input.trim());
    final parsed = _parseDescriptor(selection.locator);
    final descriptor = parsed.valueOrNull;
    if (descriptor == null) {
      return _copyFailure<GitSourceDescriptor, ParsedGitSource>(
        parsed.failureOrNull!,
      );
    }
    return GitTransportSuccess(
      ParsedGitSource(
        descriptor: descriptor,
        skillFilter: selection.skillFilter,
      ),
    );
  }

  GitTransportResult<GitSourceDescriptor> _parseDescriptor(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return _rejected('emptyLocator');
    }

    final fragment = _splitFragment(trimmed);
    final locator = fragment.locator;

    if (_isNormalizedLocalPath(locator)) {
      return _success(locator, ref: fragment.ref);
    }

    if (locator.toLowerCase().startsWith('ext::')) {
      return _rejected('unsupportedTransport');
    }
    if (RegExp(
      r'/(?:%2e|\.)(?:%2e|\.)(?:/|$)',
      caseSensitive: false,
    ).hasMatch(locator)) {
      return _rejected('invalidRepositorySubpath');
    }

    final githubPrefix = RegExp(
      r'^github:(.+)$',
      caseSensitive: false,
    ).firstMatch(locator);
    if (githubPrefix != null) {
      return _parseGitHubShorthand(githubPrefix.group(1)!, ref: fragment.ref);
    }

    final gitlabPrefix = RegExp(
      r'^gitlab:(.+)$',
      caseSensitive: false,
    ).firstMatch(locator);
    if (gitlabPrefix != null) {
      return _parseGitLabShorthand(gitlabPrefix.group(1)!, ref: fragment.ref);
    }

    final scpLike = RegExp(r'^([^@/\s]+)@[^:/\s]+:.+$').firstMatch(locator);
    if (scpLike != null) {
      if (scpLike.group(1)!.contains(':')) {
        return _rejected('embeddedCredentials');
      }
      return _success(locator, ref: fragment.ref);
    }

    final uri = Uri.tryParse(locator);
    if (uri != null && uri.hasScheme) {
      return _parseUri(uri, ref: fragment.ref);
    }

    return _parseGitHubShorthand(locator, ref: fragment.ref);
  }

  GitTransportResult<GitSourceDescriptor> _parseUri(Uri uri, {String? ref}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'ssh') {
      return _rejected('unsupportedTransport');
    }
    if (uri.host.isEmpty ||
        uri.pathSegments.where((part) => part.isNotEmpty).isEmpty) {
      return _rejected('invalidLocator');
    }
    if (uri.userInfo.contains(':') ||
        (scheme == 'https' && uri.userInfo.isNotEmpty) ||
        uri.hasQuery) {
      return _rejected('embeddedCredentials');
    }

    if (scheme == 'https' && uri.host.toLowerCase() == 'github.com') {
      return _parseGitHubUri(uri, ref: ref);
    }
    if (scheme == 'https' &&
        (uri.host.toLowerCase() == 'gitlab.com' ||
            _looksLikeGitLabTree(uri.pathSegments))) {
      return _parseGitLabUri(uri, ref: ref);
    }

    return _success(uri.toString(), ref: ref);
  }

  GitTransportResult<GitSourceDescriptor> _parseGitHubUri(
    Uri uri, {
    String? ref,
  }) {
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) {
      return _rejected('invalidLocator');
    }

    final owner = parts[0];
    final repository = _withoutGitSuffix(parts[1]);
    if (!_validPathPart(owner) || !_validPathPart(repository)) {
      return _rejected('invalidLocator');
    }

    var resolvedRef = ref;
    var subpath = '';
    if (parts.length >= 4 && parts[2] == 'tree') {
      resolvedRef = parts[3];
      if (parts.length > 4) {
        if (!_safeSubpath(parts.skip(4))) {
          return _rejected('invalidRepositorySubpath');
        }
        subpath = _normalizedSubpath(parts.skip(4));
      }
    }

    return _success(
      'https://github.com/$owner/$repository.git',
      ref: resolvedRef,
      repositorySubpath: subpath,
    );
  }

  GitTransportResult<GitSourceDescriptor> _parseGitLabUri(
    Uri uri, {
    String? ref,
  }) {
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final treeMarker = _treeMarkerIndex(parts);
    final repositoryParts = treeMarker < 0 ? parts : parts.take(treeMarker);
    final repositoryPath = repositoryParts.join('/');
    if (repositoryParts.length < 2 ||
        repositoryParts.any((part) => !_validPathPart(part))) {
      return _rejected('invalidLocator');
    }

    var resolvedRef = ref;
    var subpath = '';
    if (treeMarker >= 0) {
      if (parts.length <= treeMarker + 2) {
        return _rejected('invalidLocator');
      }
      resolvedRef = parts[treeMarker + 2];
      if (parts.length > treeMarker + 3) {
        if (!_safeSubpath(parts.skip(treeMarker + 3))) {
          return _rejected('invalidRepositorySubpath');
        }
        subpath = _normalizedSubpath(parts.skip(treeMarker + 3));
      }
    }

    final cleanPath = _withoutGitSuffix(repositoryPath);
    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    return _success(
      '${uri.scheme}://$authority/$cleanPath.git',
      ref: resolvedRef,
      repositorySubpath: subpath,
    );
  }

  GitTransportResult<GitSourceDescriptor> _parseGitHubShorthand(
    String shorthand, {
    String? ref,
  }) {
    final parts = shorthand
        .split('/')
        .where((part) => part.isNotEmpty)
        .map(_decodeComponent)
        .toList();
    if (parts.length < 2 || parts.any((part) => !_validPathPart(part))) {
      return _rejected('invalidLocator');
    }

    final owner = parts[0];
    final repository = _withoutGitSuffix(parts[1]);
    return _success(
      'https://github.com/$owner/$repository.git',
      ref: ref,
      repositorySubpath: _normalizedSubpath(parts.skip(2)),
    );
  }

  GitTransportResult<GitSourceDescriptor> _parseGitLabShorthand(
    String shorthand, {
    String? ref,
  }) {
    final parts = shorthand
        .split('/')
        .where((part) => part.isNotEmpty)
        .map(_decodeComponent)
        .toList();
    if (parts.length < 2 || parts.any((part) => !_validPathPart(part))) {
      return _rejected('invalidLocator');
    }

    final repositoryPath = _withoutGitSuffix(parts.join('/'));
    return _success('https://gitlab.com/$repositoryPath.git', ref: ref);
  }

  GitTransportResult<GitSourceDescriptor> _success(
    String locator, {
    String? ref,
    String repositorySubpath = '',
  }) => GitTransportSuccess(
    GitSourceDescriptor(
      locator: locator,
      ref: ref,
      repositorySubpath: repositorySubpath,
    ),
  );

  GitTransportResult<GitSourceDescriptor> _rejected(String reason) =>
      GitTransportFailure(
        code: GitTransportFailureCode.rejected,
        context: {'reason': reason},
        diagnostic: 'The Git source locator is not supported.',
      );
}

bool _isNormalizedLocalPath(String value) {
  if (value.contains('\u0000')) return false;
  if (value.startsWith('/')) {
    return _hasNormalizedPathSegments(value.substring(1).split('/'));
  }
  if (RegExp(r'^[A-Za-z]:\\').hasMatch(value)) {
    return _hasNormalizedPathSegments(value.substring(3).split(r'\\'));
  }
  if (value.startsWith(r'\\')) {
    final segments = value.substring(2).split(r'\\');
    return segments.length >= 2 && _hasNormalizedPathSegments(segments);
  }
  return false;
}

bool _hasNormalizedPathSegments(Iterable<String> segments) => segments.every(
  (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
);

final class _SkillSelectionParts {
  const _SkillSelectionParts({required this.locator, this.skillFilter});

  final String locator;
  final String? skillFilter;
}

_SkillSelectionParts _splitSkillSelection(String input) {
  final hashIndex = input.indexOf('#');
  if (hashIndex >= 0) {
    final locator = input.substring(0, hashIndex);
    final fragment = input.substring(hashIndex + 1);
    if (_fragmentSelectsGitRef(locator)) {
      final atIndex = fragment.indexOf('@');
      if (atIndex >= 0) {
        final ref = fragment.substring(0, atIndex);
        final filter = fragment.substring(atIndex + 1);
        return _SkillSelectionParts(
          locator: ref.isEmpty ? locator : '$locator#$ref',
          skillFilter: filter.isEmpty ? null : _decodeComponent(filter),
        );
      }
    }
  }

  final shorthand = RegExp(
    r'^(github:)?([^/:\s]+)/([^/@\s]+)@(.+)$',
    caseSensitive: false,
  ).firstMatch(input);
  if (shorthand != null) {
    final prefix = shorthand.group(1) ?? '';
    return _SkillSelectionParts(
      locator: '$prefix${shorthand.group(2)}/${shorthand.group(3)}',
      skillFilter: _decodeComponent(shorthand.group(4)!),
    );
  }
  return _SkillSelectionParts(locator: input);
}

final class _FragmentParts {
  const _FragmentParts({required this.locator, this.ref});

  final String locator;
  final String? ref;
}

_FragmentParts _splitFragment(String input) {
  final index = input.indexOf('#');
  if (index < 0) {
    return _FragmentParts(locator: input);
  }
  final locator = input.substring(0, index);
  final encodedRef = input.substring(index + 1);
  if (encodedRef.isEmpty || !_fragmentSelectsGitRef(locator)) {
    return _FragmentParts(locator: input);
  }
  return _FragmentParts(locator: locator, ref: _decodeComponent(encodedRef));
}

bool _fragmentSelectsGitRef(String locator) {
  final lower = locator.toLowerCase();
  if (lower.startsWith('github:') ||
      lower.startsWith('gitlab:') ||
      lower.startsWith('ssh://') ||
      RegExp(r'^[^@/\s]+@[^:/\s]+:.+$').hasMatch(locator)) {
    return true;
  }

  final uri = Uri.tryParse(locator);
  if (uri != null && uri.hasScheme) {
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (uri.host.toLowerCase() == 'github.com') {
      return parts.length == 2 || (parts.length >= 4 && parts[2] == 'tree');
    }
    if (uri.host.toLowerCase() == 'gitlab.com' ||
        _treeMarkerIndex(parts) >= 0) {
      return parts.length >= 2;
    }
    return uri.path.toLowerCase().endsWith('.git');
  }

  return RegExp(r'^[^/]+/[^/]+(?:/.+)?$').hasMatch(locator);
}

bool _looksLikeGitLabTree(List<String> parts) => _treeMarkerIndex(parts) >= 0;

int _treeMarkerIndex(List<String> parts) {
  for (var index = 0; index + 1 < parts.length; index += 1) {
    if (parts[index] == '-' && parts[index + 1] == 'tree') {
      return index;
    }
  }
  return -1;
}

String _withoutGitSuffix(String value) => value.toLowerCase().endsWith('.git')
    ? value.substring(0, value.length - 4)
    : value;

String _normalizedSubpath(Iterable<String> parts) =>
    parts.where((part) => part.isNotEmpty && part != '.').join('/');

bool _safeSubpath(Iterable<String> parts) => parts.every(
  (part) =>
      part.isNotEmpty &&
      part != '..' &&
      !part.contains('/') &&
      !part.contains(r'\'),
);

String _decodeComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}

bool _validPathPart(String value) =>
    value.isNotEmpty && value != '.' && value != '..' && !value.contains(r'\');

GitTransportFailure<TTarget> _copyFailure<TSource, TTarget>(
  GitTransportFailure<TSource> failure,
) => GitTransportFailure<TTarget>(
  code: failure.code,
  context: failure.context,
  diagnostic: failure.diagnostic,
);
