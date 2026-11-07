import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';

final class ParsedSkillSourceInput {
  ParsedSkillSourceInput({
    required this.draft,
    required this.detection,
    Set<String> requestedSkillNames = const {},
    this.requestGlobalScope = false,
    List<String> requestedAgentIds = const [],
    List<String> ignoredFlags = const [],
    this.fromInstallCommand = false,
  }) : requestedSkillNames = Set.unmodifiable(requestedSkillNames),
       requestedAgentIds = List.unmodifiable(requestedAgentIds),
       ignoredFlags = List.unmodifiable(ignoredFlags);

  final SkillSourceDraft draft;
  final SkillSourceDetection detection;
  final Set<String> requestedSkillNames;
  final bool requestGlobalScope;
  final List<String> requestedAgentIds;
  final List<String> ignoredFlags;
  final bool fromInstallCommand;

  @override
  String toString() =>
      'ParsedSkillSourceInput(kind: ${draft.kind.name}, '
      'locator: ${draft.locator}, ref: ${draft.sourceRef}, '
      'subpath: ${draft.repositorySubpath}, detection: ${detection.name}, '
      'skills: $requestedSkillNames, global: $requestGlobalScope, '
      'agents: $requestedAgentIds, ignoredFlags: $ignoredFlags, '
      'fromInstallCommand: $fromInstallCommand)';
}

final class SkillSourceInputParser {
  SkillSourceInputParser({String? homePath})
    : _locatorResolver = SkillSourceLocatorResolver(homePath: homePath);

  final SkillSourceLocatorResolver _locatorResolver;

  ParsedSkillSourceInput parse(
    String input, {
    required SkillSourceInputMode mode,
    SkillSourceKind? typedKind,
  }) {
    if (mode == SkillSourceInputMode.typed && typedKind == null) {
      throw ArgumentError.notNull('typedKind');
    }

    final arguments = SkillSourceLocatorResolver.installCommandArguments(
      input.trimLeft(),
    );
    final skills = <String>{};
    final agents = <String>[];
    final ignored = <String>[];
    var global = false;
    var source = arguments == null ? input.trim() : '';
    if (arguments != null) {
      final tokens = _tokenize(arguments);
      var hasSource = false;
      for (var i = 0; i < tokens.length; i++) {
        final token = tokens[i];
        switch (token) {
          case '-s' || '--skill' || '-a' || '--agent' || '--subagent':
            if (token == '--subagent') ignored.add(token);
            while (i + 1 < tokens.length && !tokens[i + 1].startsWith('-')) {
              final value = tokens[++i];
              switch (token) {
                case '-s' || '--skill':
                  skills.add(value);
                case '-a' || '--agent':
                  agents.add(value);
                case '--subagent':
                  ignored.add(value);
              }
            }
          case '--metadata':
            ignored.add(token);
            if (i + 1 < tokens.length) ignored.add(tokens[++i]);
          case '-g' || '--global':
            global = true;
          case '--all':
            skills.add('*');
            agents.add('*');
            global = true;
          default:
            if (token.startsWith('-') || hasSource) {
              ignored.add(token);
            } else {
              source = token;
              hasSource = true;
            }
        }
      }
    }

    final (detectedDraft, detection) = _detect(
      SkillSourceLocatorResolver.normalizeLocalLocatorInput(source),
      skills,
    );
    final draft = mode == SkillSourceInputMode.smart
        ? detectedDraft
        : SkillSourceDraft(
            kind: typedKind!,
            locator: switch (typedKind) {
              SkillSourceKind.local =>
                SkillSourceLocatorResolver.normalizeLocalLocatorInput(source),
              SkillSourceKind.git =>
                SkillSourceLocatorResolver.normalizeGitLocatorInput(source),
              SkillSourceKind.wellKnown => source.trim(),
            },
          );
    if (skills.contains('*')) {
      skills
        ..clear()
        ..add('*');
    }
    if (agents.contains('*')) {
      agents
        ..clear()
        ..add('*');
    }
    return ParsedSkillSourceInput(
      draft: draft,
      detection: detection,
      requestedSkillNames: skills,
      requestGlobalScope: global,
      requestedAgentIds: agents,
      ignoredFlags: ignored,
      fromInstallCommand: arguments != null,
    );
  }

  (SkillSourceDraft, SkillSourceDetection) _detect(
    String source,
    Set<String> skills,
  ) {
    if (source.isEmpty) {
      return (const SkillSourceDraft(), SkillSourceDetection.empty);
    }
    if (_isLocal(source)) {
      var locator = source;
      if (source == '~' || source.startsWith('~/')) {
        try {
          locator = _locatorResolver
              .resolve(
                SkillSourceDraft(kind: SkillSourceKind.local, locator: source),
              )
              .value;
        } on SkillAcquisitionException {
          // Leave an unavailable home for the ordinary resolver to report.
        }
      }
      return (
        SkillSourceDraft(kind: SkillSourceKind.local, locator: locator),
        SkillSourceDetection.local,
      );
    }

    final sourceUri = Uri.tryParse(source);
    if (_isWeb(source) &&
        !_isRemote(source) &&
        !_hostedHosts.contains(sourceUri?.host.toLowerCase())) {
      return (
        SkillSourceDraft(kind: SkillSourceKind.wellKnown, locator: source),
        SkillSourceDetection.webUrl,
      );
    }

    // Strip selections before normalizing; page-anchor cleanup must not hide
    // a ref or Skill selection, and SSH userinfo must stay intact.
    var value = source;
    final fragmentIndex = value.indexOf('#');
    final selectionIndex = value.lastIndexOf('@');
    if (selectionIndex > 0 &&
        ((fragmentIndex >= 0 && selectionIndex > fragmentIndex) ||
            _shorthand.hasMatch(value.substring(0, selectionIndex)))) {
      final name = value.substring(selectionIndex + 1);
      if (name.isNotEmpty && !name.contains('/') && !name.contains('#')) {
        skills.add(_decode(name));
        value = value.substring(0, selectionIndex);
      }
    }

    final normalized = SkillSourceLocatorResolver.normalizeGitLocatorInput(
      value,
    );
    final uri = Uri.tryParse(normalized);
    final hosted =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        _hostedHosts.contains(uri.host.toLowerCase());
    final remote = _isRemote(value);
    final shorthand = !hosted && _shorthand.hasMatch(value.split('#').first);
    final web = !hosted && !remote && !shorthand && _isWeb(value);
    if (web) {
      // A web fragment is page state; only Git-looking sources carry refs.
      return (
        SkillSourceDraft(kind: SkillSourceKind.wellKnown, locator: source),
        SkillSourceDetection.webUrl,
      );
    }

    var locator = hosted ? normalized : value;
    var sourceRef = '';
    final hash = locator.indexOf('#');
    if (hash >= 0) {
      sourceRef = _decode(locator.substring(hash + 1));
      locator = locator.substring(0, hash);
    }
    var subpath = '';
    if (shorthand) {
      final segments = locator.split('/');
      locator = segments.take(2).join('/');
      subpath = segments.skip(2).join('/');
    } else if (hosted) {
      final address = Uri.parse(locator);
      final segments = address.pathSegments.toList();
      final gitlab = address.host.toLowerCase().contains('gitlab');
      final marker = gitlab ? segments.indexOf('-') : 2;
      final tree = gitlab ? marker + 1 : marker;
      final hasTree =
          marker >= 2 && tree + 1 < segments.length && segments[tree] == 'tree';
      final repositorySegments = hasTree
          ? segments.take(marker).toList()
          : segments;
      if (hasTree) {
        sourceRef = segments[tree + 1];
        subpath = segments.skip(tree + 2).join('/');
      }
      if (repositorySegments.isNotEmpty &&
          repositorySegments.last.endsWith('.git')) {
        repositorySegments[repositorySegments.length - 1] = repositorySegments
            .last
            .substring(0, repositorySegments.last.length - 4);
      }
      locator = address.replace(pathSegments: repositorySegments).toString();
    }
    return (
      SkillSourceDraft(
        kind: SkillSourceKind.git,
        locator: locator,
        sourceRef: sourceRef,
        repositorySubpath: subpath,
      ),
      hosted
          ? SkillSourceDetection.gitHostedUrl
          : shorthand
          ? SkillSourceDetection.gitShorthand
          : SkillSourceDetection.gitRemote,
    );
  }

  static bool _isLocal(String value) =>
      p.posix.isAbsolute(value) ||
      (p.windows.isAbsolute(value) && !p.windows.isRootRelative(value)) ||
      value == '~' ||
      value.startsWith('~/') ||
      value.startsWith('./') ||
      value.startsWith('../') ||
      value.toLowerCase().startsWith('file://');

  static bool _isWeb(String value) =>
      RegExp(r'^https?://', caseSensitive: false).hasMatch(value);

  static bool _isRemote(String value) =>
      value.split('#').first.endsWith('.git') ||
      RegExp(
        r'^(?:git@|ssh://|github:|gitlab:)',
        caseSensitive: false,
      ).hasMatch(value);

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  static final _shorthand = RegExp(
    r'^[^./:@#\s][^/:@#\s]*/[^/:@#\s]+(?:/[^/:@#\s]+)*$',
  );
  static const _hostedHosts = {
    'github.com',
    'www.github.com',
    'gitlab.com',
    'www.gitlab.com',
  };

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    var current = StringBuffer();
    String? quote;
    var started = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == r'\' && quote != "'" && i + 1 < input.length) {
        final next = input[i + 1];
        if (next == ' ' || (quote == '"' && (next == '"' || next == r'\'))) {
          current.write(next);
          started = true;
          i++;
          continue;
        }
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
        started = true;
      } else if (char == "'" || char == '"') {
        quote = char;
        started = true;
      } else if (char.trim().isEmpty) {
        if (started) {
          tokens.add(current.toString());
          current = StringBuffer();
          started = false;
        }
      } else {
        current.write(char);
        started = true;
      }
    }
    if (started) tokens.add(current.toString());
    return tokens;
  }
}
