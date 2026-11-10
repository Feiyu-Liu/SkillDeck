import '../data/write_command_handlers.dart';
import 'command_line_activity.dart';

/// Reports Command Host write batches into the activity the App shows.
final class CommandLineActivityReporter implements WriteActivityReporter {
  CommandLineActivityReporter({
    required CommandLineActivityController Function() controller,
    required String Function(String agentId) agentName,
  }) : _controller = controller,
       _agentName = agentName;

  final CommandLineActivityController Function() _controller;
  final String Function(String agentId) _agentName;

  @override
  WriteActivity begin({
    required String command,
    required bool favorite,
    required List<String> agentIds,
    required List<WriteActivityItem> items,
    required void Function() cancel,
  }) {
    final kind = switch (command) {
      'remove' => CommandLineActivityKind.remove,
      'source replace' ||
      'source relink' => CommandLineActivityKind.replaceSource,
      'install' => CommandLineActivityKind.install,
      'update' => CommandLineActivityKind.update,
      'activate' => CommandLineActivityKind.activate,
      'deactivate' => CommandLineActivityKind.deactivate,
      'favorite' =>
        favorite
            ? CommandLineActivityKind.favorite
            : CommandLineActivityKind.unfavorite,
      'note' => CommandLineActivityKind.note,
      'tag add' => CommandLineActivityKind.tagAdd,
      'tag remove' => CommandLineActivityKind.tagRemove,
      _ => null,
    };
    if (kind == null) return const _Unreported();
    return _ReportedActivity(
      _controller().begin(
        kind: kind,
        agentNames: [for (final id in agentIds) _agentName(id)],
        items: [
          for (final skill in items)
            CommandLineActivityItem(skillId: skill.id, slotKey: skill.slotKey),
        ],
        onCancel: cancel,
      ),
    );
  }
}

final class _ReportedActivity implements WriteActivity {
  const _ReportedActivity(this._session);

  final CommandLineActivitySession _session;

  @override
  void start(String id) => _session.start(id);

  @override
  void finish(String id, String outcome, {String? errorCode}) =>
      _session.finish(id, switch (outcome) {
        'succeeded' => CommandLineItemStatus.succeeded,
        'unchanged' => CommandLineItemStatus.unchanged,
        'committedFinalizationPending' =>
          CommandLineItemStatus.committedFinalizationPending,
        'notAttempted' => CommandLineItemStatus.notAttempted,
        'cancelled' => CommandLineItemStatus.cancelled,
        _ => CommandLineItemStatus.failed,
      }, errorCode: errorCode);

  @override
  void end() => _session.end();
}

final class _Unreported implements WriteActivity {
  const _Unreported();

  @override
  void start(String id) {}

  @override
  void finish(String id, String outcome, {String? errorCode}) {}

  @override
  void end() {}
}
