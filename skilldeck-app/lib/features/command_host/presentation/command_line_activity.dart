import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a Command Host write request is doing to its Skills, as the App shows
/// it. Requests that change no Skill, such as a tag rename, report nothing.
///
/// The CLI carries no caller identity (ADR-0111), so the App only ever says
/// "the command line" and describes the command itself.
enum CommandLineActivityKind {
  activate,
  deactivate,
  favorite,
  unfavorite,
  note,
  tagAdd,
  tagRemove,
  install,
  update,
  remove,
  replaceSource,
}

enum CommandLineItemStatus {
  queued,
  running,
  succeeded,
  unchanged,
  committedFinalizationPending,
  failed,
  notAttempted,
  cancelled;

  bool get isTerminal => this != queued && this != running;

  /// Committed work, including a commit whose cleanup is still pending.
  bool get isCommitted =>
      this == succeeded || this == committedFinalizationPending;
}

@immutable
final class CommandLineActivityItem {
  const CommandLineActivityItem({
    required this.skillId,
    required this.slotKey,
    this.status = CommandLineItemStatus.queued,
    this.errorCode,
  });

  /// `WorkspaceSkillId.value`; the key cards look themselves up by.
  final String skillId;
  final String slotKey;
  final CommandLineItemStatus status;

  /// A stable Command Host error code, never raw exception text.
  final String? errorCode;

  CommandLineActivityItem _with(
    CommandLineItemStatus status, {
    String? errorCode,
  }) => CommandLineActivityItem(
    skillId: skillId,
    slotKey: slotKey,
    status: status,
    errorCode: errorCode,
  );

  @override
  bool operator ==(Object other) =>
      other is CommandLineActivityItem &&
      other.skillId == skillId &&
      other.slotKey == slotKey &&
      other.status == status &&
      other.errorCode == errorCode;

  @override
  int get hashCode => Object.hash(skillId, slotKey, status, errorCode);
}

/// One Command Host write request, from its first item to its summary.
@immutable
final class CommandLineActivity {
  CommandLineActivity({
    required this.id,
    required this.kind,
    required List<CommandLineActivityItem> items,
    List<String> agentNames = const [],
    this.finished = false,
    this.cancelling = false,
  }) : items = List.unmodifiable(items),
       agentNames = List.unmodifiable(agentNames);

  final int id;
  final CommandLineActivityKind kind;
  final List<String> agentNames;
  final List<CommandLineActivityItem> items;
  final bool finished;
  final bool cancelling;

  int get total => items.length;
  int get completed => items.where((item) => item.status.isTerminal).length;
  int get committedCount =>
      items.where((item) => item.status.isCommitted).length;
  List<CommandLineActivityItem> get failures => [
    for (final item in items)
      if (item.status == CommandLineItemStatus.failed) item,
  ];
  bool get wasCancelled =>
      items.any((item) => item.status == CommandLineItemStatus.cancelled);
  CommandLineActivityItem? get current => items
      .where((item) => item.status == CommandLineItemStatus.running)
      .firstOrNull;

  CommandLineActivityItem? itemFor(String skillId) =>
      items.where((item) => item.skillId == skillId).firstOrNull;

  CommandLineActivity _copy({
    List<CommandLineActivityItem>? items,
    bool? finished,
    bool? cancelling,
  }) => CommandLineActivity(
    id: id,
    kind: kind,
    agentNames: agentNames,
    items: items ?? this.items,
    finished: finished ?? this.finished,
    cancelling: cancelling ?? this.cancelling,
  );
}

/// How long a fully successful summary stays before it dismisses itself.
/// A summary with failures stays until the user closes it.
final commandLineSummaryLifetimeProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 6),
);

final commandLineActivityProvider =
    NotifierProvider<CommandLineActivityController, CommandLineActivity?>(
      CommandLineActivityController.new,
    );

/// True while a command-line write is running, so waiting GUI operations can
/// say what they are waiting for.
final commandLineBusyProvider = Provider<bool>(
  (ref) => ref.watch(
    commandLineActivityProvider.select(
      (activity) => activity != null && !activity.finished,
    ),
  ),
);

/// Owns the one visible command-line activity. The Command Host reports into
/// it through a [CommandLineActivitySession]; widgets only read it.
final class CommandLineActivityController
    extends Notifier<CommandLineActivity?> {
  Timer? _dismissTimer;
  VoidCallback? _onCancel;
  var _nextId = 0;

  @override
  CommandLineActivity? build() {
    ref.onDispose(() => _dismissTimer?.cancel());
    return null;
  }

  CommandLineActivitySession begin({
    required CommandLineActivityKind kind,
    required List<CommandLineActivityItem> items,
    List<String> agentNames = const [],
    VoidCallback? onCancel,
  }) {
    _dismissTimer?.cancel();
    _onCancel = onCancel;
    final id = ++_nextId;
    state = CommandLineActivity(
      id: id,
      kind: kind,
      agentNames: agentNames,
      items: [
        for (final item in items) item._with(CommandLineItemStatus.queued),
      ],
    );
    return CommandLineActivitySession._(this, id);
  }

  /// Asks the running request to stop; its items report `cancelled` later.
  void cancel() {
    final current = state;
    if (current == null || current.finished || current.cancelling) return;
    state = current._copy(cancelling: true);
    _onCancel?.call();
  }

  void dismiss() {
    _dismissTimer?.cancel();
    final current = state;
    // A running request keeps its indicator; only a summary can be closed.
    if (current == null || !current.finished) return;
    state = null;
  }

  void _update(
    int id,
    String skillId,
    CommandLineItemStatus status, {
    String? errorCode,
  }) {
    final current = state;
    if (current == null || current.id != id || current.finished) return;
    state = current._copy(
      items: [
        for (final item in current.items)
          item.skillId == skillId
              ? item._with(status, errorCode: errorCode)
              : item,
      ],
    );
  }

  void _end(int id) {
    final current = state;
    if (current == null || current.id != id || current.finished) return;
    // Anything the request never reached did not run.
    final ended = current._copy(
      finished: true,
      cancelling: false,
      items: [
        for (final item in current.items)
          item.status.isTerminal
              ? item
              : item._with(
                  current.cancelling
                      ? CommandLineItemStatus.cancelled
                      : CommandLineItemStatus.notAttempted,
                ),
      ],
    );
    state = ended;
    _onCancel = null;
    if (ended.failures.isEmpty && !ended.wasCancelled) {
      _dismissTimer = Timer(ref.read(commandLineSummaryLifetimeProvider), () {
        if (state?.id == id) state = null;
      });
    }
  }
}

/// The Command Host's handle on one activity. Calls after a newer activity
/// began, or after [end], are ignored.
final class CommandLineActivitySession {
  CommandLineActivitySession._(this._controller, this._id);

  final CommandLineActivityController _controller;
  final int _id;

  void start(String skillId) =>
      _controller._update(_id, skillId, CommandLineItemStatus.running);

  void finish(
    String skillId,
    CommandLineItemStatus status, {
    String? errorCode,
  }) {
    assert(status.isTerminal, 'finish needs a terminal status');
    _controller._update(_id, skillId, status, errorCode: errorCode);
  }

  void end() => _controller._end(_id);
}
