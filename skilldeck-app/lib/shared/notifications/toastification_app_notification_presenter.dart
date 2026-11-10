import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/widgets/app_notification_toast.dart';
import 'package:toastification/toastification.dart';

final class ToastificationAppNotificationPresenter
    implements AppNotificationPresenter {
  final Set<ToastificationItem> _transientItems = {};
  final Map<int, _TaskToastEntry> _tasks = {};
  var _disposed = false;

  @override
  void present(AppNotificationPresentation presentation) {
    if (_disposed) return;
    switch (presentation.kind) {
      case AppNotificationPresentationKind.transient:
        _showTransient(presentation.content);
      case AppNotificationPresentationKind.taskStarted:
        _startTask(presentation.taskId!, presentation.content);
      case AppNotificationPresentationKind.taskUpdated:
        _updateTask(presentation.taskId!, presentation.content);
      case AppNotificationPresentationKind.taskFinished:
        _finishTask(presentation.taskId!, presentation.content);
      case AppNotificationPresentationKind.taskDismissed:
        _dismissTask(presentation.taskId!);
    }
  }

  void _showTransient(AppNotificationContent content) {
    late final ToastificationItem item;
    item = toastification.showCustom(
      autoCloseDuration: _duration(content.severity),
      animationDuration: const Duration(milliseconds: 260),
      animationBuilder: _animationBuilder,
      callbacks: ToastificationCallbacks(
        onDismissed: _transientItems.remove,
        onAutoCompleteCompleted: _transientItems.remove,
      ),
      builder: (context, holder) => AppNotificationToast(
        content: content,
        onClose: () => toastification.dismiss(holder),
        onPause: holder.pause,
        onResume: holder.start,
      ),
    );
    _transientItems.add(item);
  }

  void _startTask(int taskId, AppNotificationContent content) {
    _dismissTask(taskId, showRemoveAnimation: false);
    final entry = _TaskToastEntry(content);
    late final ToastificationItem item;
    item = toastification.showCustom(
      animationDuration: const Duration(milliseconds: 260),
      animationBuilder: _animationBuilder,
      callbacks: ToastificationCallbacks(
        onDismissed: (_) => _removeTask(taskId),
      ),
      builder: (context, holder) => ValueListenableBuilder(
        valueListenable: entry.content,
        builder: (context, current, child) => AppNotificationToast(
          content: current,
          onClose: current.taskRunning ? null : () => _dismissTask(taskId),
          onPause: entry.pause,
          onResume: entry.resume,
        ),
      ),
    );
    entry.item = item;
    _tasks[taskId] = entry;
  }

  void _updateTask(int taskId, AppNotificationContent content) {
    final entry = _tasks[taskId];
    if (entry == null) {
      _startTask(taskId, content);
      return;
    }
    entry.update(content);
  }

  void _finishTask(int taskId, AppNotificationContent content) {
    final entry = _tasks[taskId];
    if (entry == null) {
      _showTransient(content);
      return;
    }
    entry
      ..update(content)
      ..scheduleDismiss(
        _duration(content.severity),
        () => _dismissTask(taskId),
      );
  }

  void _dismissTask(int taskId, {bool showRemoveAnimation = true}) {
    final entry = _tasks.remove(taskId);
    if (entry == null) return;
    final item = entry.item;
    entry.dispose();
    if (item != null) {
      toastification.dismiss(item, showRemoveAnimation: showRemoveAnimation);
    }
  }

  void _removeTask(int taskId) {
    _tasks.remove(taskId)?.dispose();
  }

  @override
  void dismissAll() {
    for (final item in _transientItems.toList(growable: false)) {
      toastification.dismiss(item, showRemoveAnimation: false);
    }
    _transientItems.clear();
    for (final entry in _tasks.values.toList(growable: false)) {
      final item = entry.item;
      entry.dispose();
      if (item != null) {
        toastification.dismiss(item, showRemoveAnimation: false);
      }
    }
    _tasks.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    dismissAll();
  }

  Widget _animationBuilder(
    BuildContext context,
    Animation<double> animation,
    Alignment alignment,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.12),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  Duration _duration(AppNotificationSeverity severity) => switch (severity) {
    AppNotificationSeverity.success => const Duration(seconds: 3),
    AppNotificationSeverity.info => const Duration(seconds: 4),
    AppNotificationSeverity.warning => const Duration(seconds: 6),
    AppNotificationSeverity.error => const Duration(seconds: 8),
  };
}

final class _TaskToastEntry {
  _TaskToastEntry(AppNotificationContent initial)
    : content = ValueNotifier(initial);

  final ValueNotifier<AppNotificationContent> content;
  ToastificationItem? item;

  Timer? _timer;
  Stopwatch? _stopwatch;
  Duration? _remaining;
  VoidCallback? _onElapsed;
  var _hovering = false;
  var _disposed = false;

  void update(AppNotificationContent next) {
    if (_disposed) return;
    content.value = next;
  }

  void scheduleDismiss(Duration duration, VoidCallback onElapsed) {
    if (_disposed) return;
    _timer?.cancel();
    _remaining = duration;
    _onElapsed = onElapsed;
    if (!_hovering) _startTimer();
  }

  void pause() {
    _hovering = true;
    final timer = _timer;
    final stopwatch = _stopwatch;
    final remaining = _remaining;
    if (_disposed || timer == null || stopwatch == null || remaining == null) {
      return;
    }
    timer.cancel();
    _timer = null;
    stopwatch.stop();
    _remaining = remaining - stopwatch.elapsed;
  }

  void resume() {
    _hovering = false;
    if (_disposed || _timer != null || _remaining == null) return;
    _startTimer();
  }

  void _startTimer() {
    final remaining = _remaining;
    final onElapsed = _onElapsed;
    if (_disposed || remaining == null || onElapsed == null) return;
    final effectiveRemaining = remaining.isNegative ? Duration.zero : remaining;
    _stopwatch = Stopwatch()..start();
    _timer = Timer(effectiveRemaining, () {
      _timer = null;
      _remaining = null;
      _stopwatch?.stop();
      _stopwatch = null;
      onElapsed();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _remaining = null;
    _onElapsed = null;
    content.dispose();
  }
}
