import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';

void main() {
  ProviderContainer containerWith({Duration lifetime = Duration.zero}) {
    final container = ProviderContainer(
      overrides: [
        commandLineSummaryLifetimeProvider.overrideWithValue(lifetime),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  const items = [
    CommandLineActivityItem(skillId: 'a', slotKey: 'alpha'),
    CommandLineActivityItem(skillId: 'b', slotKey: 'beta'),
    CommandLineActivityItem(skillId: 'c', slotKey: 'gamma'),
  ];

  test('tracks each item from queued to a terminal outcome', () {
    final container = containerWith();
    final controller = container.read(commandLineActivityProvider.notifier);
    final session = controller.begin(
      kind: CommandLineActivityKind.activate,
      agentNames: const ['Codex'],
      items: items,
    );

    var activity = container.read(commandLineActivityProvider)!;
    expect(
      activity.items.map((i) => i.status),
      everyElement(CommandLineItemStatus.queued),
    );
    expect(container.read(commandLineBusyProvider), isTrue);

    session.start('a');
    activity = container.read(commandLineActivityProvider)!;
    expect(activity.current?.slotKey, 'alpha');
    expect(activity.completed, 0);

    session.finish('a', CommandLineItemStatus.succeeded);
    session.start('b');
    session.finish(
      'b',
      CommandLineItemStatus.failed,
      errorCode: 'activationTargetOccupied',
    );
    activity = container.read(commandLineActivityProvider)!;
    expect(activity.completed, 2);
    expect(activity.committedCount, 1);
    expect(activity.failures.single.errorCode, 'activationTargetOccupied');
  });

  test('marks items the request never reached as not attempted', () {
    final container = containerWith();
    final session = container
        .read(commandLineActivityProvider.notifier)
        .begin(kind: CommandLineActivityKind.favorite, items: items);

    session.start('a');
    session.finish('a', CommandLineItemStatus.failed, errorCode: 'x');
    session.end();

    final activity = container.read(commandLineActivityProvider)!;
    expect(activity.finished, isTrue);
    expect(container.read(commandLineBusyProvider), isFalse);
    expect(
      activity.items.skip(1).map((i) => i.status),
      everyElement(CommandLineItemStatus.notAttempted),
    );
  });

  test('dismisses a fully successful summary on its own', () async {
    final container = containerWith();
    final session = container
        .read(commandLineActivityProvider.notifier)
        .begin(
          kind: CommandLineActivityKind.tagAdd,
          items: items.take(1).toList(),
        );
    session.start('a');
    session.finish('a', CommandLineItemStatus.succeeded);
    session.end();
    expect(container.read(commandLineActivityProvider), isNotNull);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(commandLineActivityProvider), isNull);
  });

  test('keeps a summary with failures until it is dismissed', () async {
    final container = containerWith();
    final controller = container.read(commandLineActivityProvider.notifier);
    final session = controller.begin(
      kind: CommandLineActivityKind.activate,
      items: items.take(1).toList(),
    );
    session.finish('a', CommandLineItemStatus.failed, errorCode: 'x');
    session.end();

    await Future<void>.delayed(Duration.zero);
    expect(container.read(commandLineActivityProvider), isNotNull);

    controller.dismiss();
    expect(container.read(commandLineActivityProvider), isNull);
  });

  test('a running request cannot be dismissed', () {
    final container = containerWith();
    final controller = container.read(commandLineActivityProvider.notifier);
    controller.begin(kind: CommandLineActivityKind.activate, items: items);

    controller.dismiss();

    expect(container.read(commandLineActivityProvider), isNotNull);
  });

  test('cancel asks the request to stop and its remainder ends cancelled', () {
    final container = containerWith();
    final controller = container.read(commandLineActivityProvider.notifier);
    var cancelled = 0;
    final session = controller.begin(
      kind: CommandLineActivityKind.activate,
      items: items,
      onCancel: () => cancelled++,
    );
    session.start('a');
    session.finish('a', CommandLineItemStatus.succeeded);

    controller.cancel();
    controller.cancel();
    expect(cancelled, 1);
    expect(container.read(commandLineActivityProvider)!.cancelling, isTrue);

    session.end();
    final activity = container.read(commandLineActivityProvider)!;
    expect(activity.wasCancelled, isTrue);
    expect(
      activity.items.skip(1).map((i) => i.status),
      everyElement(CommandLineItemStatus.cancelled),
    );
  });

  test('a new request replaces the previous one and ignores stale reports', () {
    final container = containerWith(lifetime: const Duration(hours: 1));
    final controller = container.read(commandLineActivityProvider.notifier);
    final first = controller.begin(
      kind: CommandLineActivityKind.activate,
      items: items.take(1).toList(),
    );
    first.end();

    final second = controller.begin(
      kind: CommandLineActivityKind.deactivate,
      items: items.skip(1).toList(),
    );
    first.start('a');
    second.start('b');

    final activity = container.read(commandLineActivityProvider)!;
    expect(activity.kind, CommandLineActivityKind.deactivate);
    expect(activity.itemFor('a'), isNull);
    expect(activity.current?.slotKey, 'beta');
  });
}
