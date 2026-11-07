import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../../skilldeck_protocol.dart';
import 'command_catalog.dart';

final class SkilldeckCommandLine {
  const SkilldeckCommandLine({
    required this.command,
    required this.json,
    required this.requestArguments,
    this.helpCommand,
    this.noLaunch = false,
  });
  final String command;
  final bool json;
  final bool noLaunch;
  final Map<String, Object?> requestArguments;
  final String? helpCommand;
}

SkilldeckCommandLine parseSkilldeckCommandLine(
  List<String> arguments, {
  required String cwd,
  required bool isWindows,
}) {
  void common(ArgParser parser) => parser
    ..addFlag('json', negatable: false)
    ..addFlag('launch', defaultsTo: true)
    ..addOption('wait', defaultsTo: '30')
    ..addFlag('help', abbr: 'h', negatable: false);
  void configure(ArgParser parser, Map spec) {
    common(parser);
    for (final entry in (spec['flags'] as Map).entries) {
      if (commonFlags.containsKey(entry.key)) continue;
      final flag = entry.value as Map;
      if (flag['type'] == 'bool') {
        parser.addFlag(
          entry.key as String,
          negatable: flag['default'] == true,
          defaultsTo: flag['default'] == true,
        );
      } else if (flag['repeatable'] == true) {
        parser.addMultiOption(entry.key as String, splitCommas: false);
      } else {
        parser.addOption(entry.key as String);
      }
    }
    for (final entry in (spec['subcommands'] as Map? ?? {}).entries) {
      configure(
        parser.addCommand(
          entry.key as String,
          ArgParser(allowTrailingOptions: true),
        ),
        entry.value as Map,
      );
    }
  }

  final parser = ArgParser(allowTrailingOptions: true);
  common(parser);
  parser.addFlag('version', negatable: false);
  for (final entry in commandCatalog.entries) {
    configure(
      parser.addCommand(entry.key, ArgParser(allowTrailingOptions: true)),
      entry.value,
    );
  }
  final parsed = parser.parse(arguments);
  final sub = parsed.command;
  final leaf = sub?.command ?? sub;
  final levels = [parsed, ?sub, if (sub?.command != null) sub!.command!];
  final json = levels.any((r) => r.flag('json'));
  for (final result in levels) {
    final wait = int.tryParse(result.option('wait')!);
    if (wait == null || wait < 0) throw const FormatException();
  }
  if (parsed.rest.isNotEmpty) throw const FormatException();
  SkilldeckCommandLine local(String command, [String? target]) =>
      SkilldeckCommandLine(
        command: command,
        json: json,
        requestArguments: const {},
        helpCommand: target,
      );
  if (parsed.flag('version')) return local('version');
  if (levels.any((r) => r.flag('help')) || sub?.name == 'help') {
    String? target = sub?.name;
    if (sub?.name == 'help') {
      if (sub!.rest.length > 1) throw const FormatException();
      target = sub.rest.firstOrNull;
    }
    helpCatalog(target);
    return local('help', target);
  }
  if (sub == null ||
      leaf == null ||
      ['tag', 'approvals', 'source'].contains(sub.name) &&
          sub.command == null) {
    throw const FormatException();
  }
  if (sub.command != null && sub.rest.isNotEmpty) throw const FormatException();
  final command = sub.command == null ? sub.name! : '${sub.name} ${leaf.name}';
  final approvalControl = sub.name == 'approvals';
  final destructive =
      command == 'remove' ||
      command == 'tag delete' ||
      command == 'source replace' ||
      command == 'source relink';
  final write =
      !approvalControl &&
      !['status', 'agents', 'list', 'show'].contains(command);
  final activation = command == 'activate' || command == 'deactivate';
  final tagAssignment = command == 'tag add' || command == 'tag remove';
  final request = <String, Object?>{};
  final paths = p.Context(
    style: isWindows ? p.Style.windows : p.Style.posix,
    current: cwd,
  );
  String sourceArgument(String source) {
    final localRelative =
        source == '.' ||
        source == '..' ||
        source.startsWith('./') ||
        source.startsWith('../') ||
        isWindows && (source.startsWith(r'.\') || source.startsWith(r'..\'));
    return localRelative ? paths.normalize(paths.absolute(source)) : source;
  }

  if (approvalControl || command == 'tag delete') {
    if (leaf.rest.length != 1 || leaf.rest.single.trim().isEmpty) {
      throw const FormatException();
    }
    request[approvalControl ? 'id' : 'tag'] = leaf.rest.single;
  } else if (command == 'install') {
    if (leaf.rest.length != 1 || leaf.rest.single.trim().isEmpty) {
      throw const FormatException();
    }
    final source = leaf.rest.single;
    request['source'] = sourceArgument(source);
    final skills = leaf.multiOption('skill');
    final allSkills = leaf.flag('all-skills');
    final agents = leaf.multiOption('agent');
    final project = leaf.option('project');
    if (skills.isNotEmpty && allSkills || project != null && agents.isEmpty) {
      throw const FormatException();
    }
    request['skills'] = skills;
    request['allSkills'] = allSkills;
    request['agents'] = agents;
    if (project != null) {
      request['projectPath'] = paths.normalize(paths.absolute(project));
    }
  } else if (command == 'tag rename') {
    if (leaf.rest.length != 2) throw const FormatException();
    request['rename'] = {'from': leaf.rest[0], 'to': leaf.rest[1]};
  } else if (command != 'status' && command != 'agents') {
    final project = leaf.option('project');
    final projectPath = project == null
        ? null
        : paths.normalize(paths.absolute(project));
    final selection = SkillSelection(
      refs: leaf.rest,
      tags: tagAssignment ? [] : leaf.multiOption('tag'),
      untagged: leaf.flag('untagged'),
      favorite: leaf.flag('favorite'),
      sourcePrefix: leaf.option('source'),
      activeFor: leaf.option('active-for'),
      projectPath: activation ? null : projectPath,
      hasUpdate: leaf.flag('has-update'),
      all: leaf.flag('all'),
    );
    if (selection.isEmpty && command != 'source relink') {
      throw const FormatException();
    }
    if (!selection.isEmpty) request['selection'] = selection.toJson();
    if (command == 'source relink') {
      if (!leaf.flag('from-skills-lock')) throw const FormatException();
      request['fromSkillsLock'] = true;
    }
    if (command == 'source replace') {
      final to = leaf.option('to');
      final ref = leaf.option('ref');
      final skill = leaf.option('skill');
      if (to == null ||
          to.trim().isEmpty ||
          ref != null && ref.trim().isEmpty ||
          skill != null &&
              (skill.trim().isEmpty || selection.refs.toSet().length > 1)) {
        throw const FormatException();
      }
      request['to'] = sourceArgument(to);
      if (ref != null) request['ref'] = ref;
      if (skill != null) request['skill'] = skill;
    }
    if (activation) {
      final agents = leaf.multiOption('agent');
      if (agents.isEmpty) throw const FormatException();
      request['agents'] = agents;
      if (projectPath != null) request['projectPath'] = projectPath;
    }
    if (command == 'show' && leaf.option('document') != null) {
      request['document'] = leaf.option('document');
    }
    if (command == 'update') request['check'] = leaf.flag('check');
    if (command == 'favorite') request['favorite'] = !leaf.flag('off');
    if (command == 'note') {
      final note = leaf.option('set');
      if ((note != null) == leaf.flag('clear')) throw const FormatException();
      request['note'] = note == null ? {'clear': true} : {'set': note};
    }
    if (tagAssignment) {
      final tags = leaf.multiOption('tag');
      if (tags.isEmpty) throw const FormatException();
      request['tags'] = tags;
    }
  } else if (leaf.rest.isNotEmpty) {
    throw const FormatException();
  }
  if (write) {
    request['dryRun'] = leaf.flag('dry-run');
    if (!destructive ||
        command == 'source replace' ||
        command == 'source relink') {
      request['keepGoing'] = leaf.flag('keep-going');
    }
    request['wait'] = int.parse(
      levels
          .lastWhere((r) => r.wasParsed('wait'), orElse: () => parsed)
          .option('wait')!,
    );
  }
  if (destructive || command == 'approvals wait') {
    final seconds = int.tryParse(leaf.option('approval-timeout') ?? '90');
    if (seconds == null || seconds < 0 || seconds > 600) {
      throw const FormatException();
    }
    request['approvalTimeout'] = seconds;
  }
  return SkilldeckCommandLine(
    command: command,
    json: json,
    requestArguments: request,
    noLaunch: levels.any((r) => !r.flag('launch')),
  );
}
