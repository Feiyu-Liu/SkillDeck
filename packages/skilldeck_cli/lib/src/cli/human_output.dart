import '../../skilldeck_protocol.dart';

/// [arguments] are the request the CLI sent; they pick wording such as
/// "unfavorited" that the result alone does not carry.
String renderHumanResult(
  CommandResult result, {
  Map<String, Object?> arguments = const {},
}) {
  if (result.command.startsWith('approvals ')) {
    if (result.data['result'] case final Map<String, Object?> terminal) {
      return renderHumanResult(CommandResult.fromJson(terminal));
    }
    if (result.data['state'] case final String state) {
      return 'Approval ${_plain('${result.data['id']}')}: $state.';
    }
  }
  if (result.error?.code == 'approvalPending') return result.error!.message;
  if (result.command == 'tag delete' && result.ok) {
    if (result.data['dryRun'] == true) {
      return 'Tag ${_plain('${result.data['tag']}')} would be deleted; '
          '${result.data['assignedSkillCount']} Skills would be unassigned (dry run, nothing changed).';
    }
    return result.data['outcome'] == 'committedFinalizationPending'
        ? 'Tag deleted, cleanup pending.'
        : 'Tag deleted.';
  }
  if (result.error?.code == 'ambiguousSource') {
    final candidates = result.error!.details['candidates'] as List? ?? [];
    return 'Pass --skill <name> or --all-skills. Candidates: '
        '${candidates.cast<Map>().map((c) => _plain('${c['slotKey']}')).join(', ')}';
  }
  final data = result.data;
  if (_writeCommands.contains(result.command)) {
    return _renderWrite(result, arguments);
  }
  switch (result.command) {
    case 'agents':
      return _table(
        ['Name', 'ID', 'Enabled', 'Global root'],
        [
          for (final agent in (data['agents'] as List).cast<Map>())
            [
              '${agent['name']}',
              '${agent['id']}',
              agent['enabled'] == true ? 'yes' : 'no',
              (agent['globalRoots'] as List).join(', '),
            ],
        ],
      );
    case 'list':
      return _table(
        ['Name', 'Slot Key', 'Active Agents', 'Tags', '★'],
        [
          for (final skill in (data['skills'] as List).cast<Map>())
            [
              '${skill['name']}',
              '${skill['slotKey']}',
              (skill['activations'] as List)
                  .cast<Map>()
                  .map((a) => a['agent'])
                  .toSet()
                  .join(', '),
              (skill['tags'] as List).join(', '),
              skill['favorite'] == true ? '★' : '',
            ],
        ],
      );
    case 'show':
      if (data['document'] case final Map document) {
        return document['text'] as String;
      }
      final skill = data['skill'] as Map;
      return [
        for (final key in [
          'name',
          'id',
          'slotKey',
          'declaredName',
          'description',
          'contentHash',
          'favorite',
          'note',
          'integrity',
        ])
          '${key.padRight(12)}  ${_plain('${skill[key] ?? ''}')}',
        'source        ${_plain('${(skill['source'] as Map)['locator']}')}',
        'tags          ${_plain((skill['tags'] as List).join(', '))}',
        'activations   ${_plain((skill['activations'] as List).cast<Map>().map((a) => '${a['agent']} (${a['scope']}${a['projectPath'] == null ? '' : ': ${a['projectPath']}'}, ${a['mode']})').join(', '))}',
        'update        ${(skill['update'] as Map)['status']}',
        'draft         ${(skill['draft'] as Map)['present']}',
        'documents     ${_plain((data['documents'] as List).join(', '))}',
      ].join('\n');
    default:
      final workspace = data['workspace'];
      if (workspace is! Map) return 'SkillDeck is running.';
      return 'SkillDeck ${data['appVersion']} — Workspace ${workspace['state']}\n'
          '${workspace['skillCount']} Skills, ${workspace['projectRootCount']} Project Roots';
  }
}

String _plain(String value) =>
    value.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ');

String _table(List<String> headers, List<List<String>> rows) {
  String cell(String value) {
    final runes = _plain(value).runes.toList();
    return runes.length <= 60
        ? String.fromCharCodes(runes)
        : '${String.fromCharCodes(runes.take(59))}…';
  }

  final all = [headers, ...rows].map((row) => row.map(cell).toList()).toList();
  final widths = List.generate(
    headers.length,
    (i) =>
        all.map((row) => row[i].runes.length).reduce((a, b) => a > b ? a : b),
  );
  return all
      .map(
        (row) => List.generate(
          headers.length,
          (i) => row[i] + ' ' * (widths[i] - row[i].runes.length),
        ).join('  ').trimRight(),
      )
      .join('\n');
}

const _writeCommands = {
  'remove',
  'source replace',
  'source relink',
  'install',
  'update',
  'activate',
  'deactivate',
  'favorite',
  'note',
  'tag add',
  'tag remove',
  'tag rename',
};

/// One line per Skill, then a summary such as `2 activated, 1 failed`.
/// The terminal belongs to the user, so naming their own Skills is fine;
/// only diagnostics must stay free of selections.
String _renderWrite(CommandResult result, Map<String, Object?> arguments) {
  final dryRun = result.data['dryRun'] == true;
  final done = switch (result.command) {
    'remove' => 'removed',
    'source replace' || 'source relink' => 'replaced',
    'install' => 'installed',
    'update' => 'updated',
    'activate' => 'activated',
    'deactivate' => 'deactivated',
    'favorite' => arguments['favorite'] == false ? 'unfavorited' : 'favorited',
    'note' => 'note updated',
    'tag add' => 'tagged',
    'tag remove' => 'untagged',
    _ => 'renamed',
  };
  String describe(String outcome) => switch (outcome) {
    'succeeded' => done,
    'wouldSucceed' => 'would be $done',
    'alreadyInstalled' => 'already installed',
    'updateAvailable' => 'update available',
    'upToDate' => 'up to date',
    'checkFailed' => 'check failed',
    'unchanged' => 'unchanged',
    'committedFinalizationPending' => '$done, cleanup pending',
    'failed' => 'failed',
    'notAttempted' => 'not attempted',
    'skipped' => 'skipped',
    'cancelled' => 'cancelled',
    _ => outcome,
  };
  var items = result.results.cast<Map<Object?, Object?>>().toList();
  if (result.command == 'source replace' || result.command == 'source relink') {
    // A relink can skip many Skills; what changed and what failed come first.
    const order = [
      'succeeded',
      'committedFinalizationPending',
      'wouldSucceed',
      'failed',
      'cancelled',
      'unchanged',
      'skipped',
    ];
    int rank(Map<Object?, Object?> item) {
      final index = order.indexOf('${item['outcome']}');
      return index < 0 ? order.length : index;
    }

    final ranked = items.indexed.toList()
      ..sort((a, b) {
        final byOutcome = rank(a.$2).compareTo(rank(b.$2));
        return byOutcome != 0 ? byOutcome : a.$1.compareTo(b.$1);
      });
    items = [for (final (_, item) in ranked) item];
  }
  final names = [
    for (final (index, item) in items.indexed)
      _plain(
        '${item['slotKey'] ?? (result.command == 'tag rename' ? 'tag' : 'item ${index + 1}')}',
      ),
  ];
  final width = names.fold(0, (w, name) => name.length > w ? name.length : w);
  final counts = <String, int>{};
  final lines = <String>[];
  for (final (index, item) in items.indexed) {
    final outcome = item['outcome']! as String;
    counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    final symbol = switch (outcome) {
      'succeeded' => '✓',
      'wouldSucceed' => '→',
      'unchanged' => '=',
      'failed' => '✗',
      'notAttempted' => '–',
      'committedFinalizationPending' => '…',
      'cancelled' => '×',
      'upToDate' => '✓',
      'updateAvailable' => '↑',
      'checkFailed' => '✗',
      _ => '·',
    };
    final code = (item['error'] as Map<Object?, Object?>?)?['code'];
    final reason = (item['reason'] as Map<Object?, Object?>?)?['code'];
    lines.add(
      '$symbol ${names[index].padRight(width)}  ${describe(outcome)}'
      '${item['from'] is Map && item['to'] is Map ? ' (${_plain('${(item['from'] as Map)['locator']}')} → ${_plain('${(item['to'] as Map)['locator']}')})' : ''}'
      '${result.command == 'remove' && dryRun ? ' (${_removalDisclosure(item)})' : ''}'
      '${(outcome == 'failed' || outcome == 'checkFailed') && code != null ? ' ($code)' : ''}'
      '${outcome == 'skipped' && reason != null ? ' ($reason)' : ''}',
    );
  }
  lines.add(
    counts.isEmpty
        ? 'Nothing matched.'
        : [
                for (final entry in counts.entries)
                  '${entry.value} ${describe(entry.key)}',
              ].join(', ') +
              (dryRun ? ' (dry run, nothing changed)' : ''),
  );
  if (result.data['sources'] case final List sources) {
    lines[lines.length - 1] += ', ${sources.length} sources inspected';
  }
  return lines.join('\n');
}

/// The same facts the App's approval sheet shows, in a few plain words.
String _removalDisclosure(Map<Object?, Object?> item) {
  final agents = (item['activatedAgents'] as List? ?? const []).join(', ');
  return [
    agents.isEmpty ? 'not active in any Agent' : 'active in ${_plain(agents)}',
    if (item['unpublishedDraft'] == true) 'has an unpublished Draft',
  ].join('; ');
}
