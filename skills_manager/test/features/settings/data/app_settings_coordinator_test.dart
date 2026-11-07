import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/data/app_settings_coordinator.dart';
import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  group('AppSettingsCoordinator', () {
    test(
      'rejects invalid complete settings before durable or runtime changes',
      () async {
        final events = <String>[];
        const invalid = AppSettings(
          customAgents: [
            CustomAgentSettings(
              id: 'custom-duplicate',
              displayName: 'First',
              iconName: 'bot',
              platforms: {
                AppDesktopPlatform.macos: CustomAgentPlatformSettings(
                  globalSkillsPath: '/tmp/first',
                ),
              },
            ),
            CustomAgentSettings(
              id: 'custom-duplicate',
              displayName: 'Second',
              iconName: 'bot',
              platforms: {
                AppDesktopPlatform.macos: CustomAgentPlatformSettings(
                  globalSkillsPath: '/tmp/second',
                ),
              },
            ),
          ],
        );
        final store = _MemoryAppSettingsStore(events: events);
        final runtime = _Runtime(events: events);
        final coordinator = AppSettingsCoordinator(
          store: store,
          runtime: runtime,
        );

        await expectLater(coordinator.save(invalid), throwsFormatException);

        expect(events, isEmpty);
        expect(store.rawValue, isNull);
        expect(runtime.requests, isEmpty);
      },
    );

    test(
      'rolls back the prior stored settings for a pre-commit failure',
      () async {
        final events = <String>[];
        const previous = AppSettings(localePreference: AppLocalePreference.zh);
        const next = AppSettings(localePreference: AppLocalePreference.en);
        const rawPrevious =
            '{"customAgents":[],"localePreference":"zh","version":1}';
        final failure = WorkspaceFailure(
          code: WorkspaceErrorCode.duplicateAgentId,
          operation: WorkspaceOperationKind.reconfigureAgentCatalog,
        );
        final store = _MemoryAppSettingsStore(
          rawValue: rawPrevious,
          events: events,
        );
        final runtime = _Runtime(
          events: events,
          completion: WorkspaceFailed(failure: failure),
        );
        final coordinator = AppSettingsCoordinator(
          store: store,
          runtime: runtime,
        );

        final completion = await coordinator.save(next);

        expect(completion, isA<WorkspaceFailed<SkillsWorkspaceSnapshot>>());
        expect(events, ['capture', 'write:en', 'reconfigure:en', 'restore']);
        expect(store.rawValue, rawPrevious);
        expect(AppSettings.decode(store.rawValue!).toJson(), previous.toJson());
        expect(runtime.requests.single.toJson(), next.toJson());
      },
    );

    test(
      'rolls back a missing preference key when runtime throws unexpectedly',
      () async {
        final events = <String>[];
        const next = AppSettings(localePreference: AppLocalePreference.zh);
        final store = _MemoryAppSettingsStore(events: events);
        final runtime = _Runtime(
          events: events,
          error: StateError('unexpected'),
        );
        final coordinator = AppSettingsCoordinator(
          store: store,
          runtime: runtime,
        );

        await expectLater(coordinator.save(next), throwsStateError);

        expect(events, ['capture', 'write:zh', 'reconfigure:zh', 'restore']);
        expect(store.rawValue, isNull);
      },
    );

    test(
      'keeps new preferences and forwards a committed-pending outcome',
      () async {
        final events = <String>[];
        const next = AppSettings(localePreference: AppLocalePreference.zh);
        final pending = WorkspaceCommittedPending<SkillsWorkspaceSnapshot>(
          operationId: 'settings-finalization',
          committedRevision: 7,
        );
        final store = _MemoryAppSettingsStore(events: events);
        final runtime = _Runtime(events: events, completion: pending);
        final forwarded =
            <WorkspaceCommittedPending<SkillsWorkspaceSnapshot>>[];
        final coordinator = AppSettingsCoordinator(
          store: store,
          runtime: runtime,
          onCommittedPending: forwarded.add,
        );

        final completion = await coordinator.save(next);

        expect(completion, same(pending));
        expect(events, ['capture', 'write:zh', 'reconfigure:zh']);
        expect(store.rawValue, isNotNull);
        expect(AppSettings.decode(store.rawValue!).toJson(), next.toJson());
        expect(forwarded, [same(pending)]);
      },
    );

    test(
      'does not roll back a committed-pending preference when handoff throws',
      () async {
        final events = <String>[];
        const next = AppSettings(localePreference: AppLocalePreference.zh);
        final pending = WorkspaceCommittedPending<SkillsWorkspaceSnapshot>(
          operationId: 'settings-handoff-error',
          committedRevision: 8,
        );
        final store = _MemoryAppSettingsStore(events: events);
        final coordinator = AppSettingsCoordinator(
          store: store,
          runtime: _Runtime(events: events, completion: pending),
          onCommittedPending: (_) => throw StateError('handoff failed'),
        );

        await expectLater(coordinator.save(next), throwsStateError);

        expect(events, ['capture', 'write:zh', 'reconfigure:zh']);
        expect(AppSettings.decode(store.rawValue!).toJson(), next.toJson());
      },
    );
  });
}

final class _MemoryAppSettingsStore implements AppSettingsStore {
  _MemoryAppSettingsStore({this.rawValue, required this.events});

  String? rawValue;
  final List<String> events;

  @override
  Future<AppSettingsStoreSnapshot> captureSnapshot() async {
    events.add('capture');
    return rawValue == null
        ? const AppSettingsStoreSnapshot.missing()
        : AppSettingsStoreSnapshot.withValue(rawValue!);
  }

  @override
  Future<AppSettings?> read() async =>
      rawValue == null ? null : AppSettings.decode(rawValue!);

  @override
  Future<void> restore(AppSettingsStoreSnapshot snapshot) async {
    events.add('restore');
    rawValue = snapshot.rawValue;
  }

  @override
  Future<void> write(AppSettings settings) async {
    events.add('write:${settings.localePreference.name}');
    rawValue = jsonEncode(settings.toJson());
  }
}

final class _Runtime implements AppSettingsRuntime {
  _Runtime({required this.events, this.completion, this.error});

  final List<String> events;
  final WorkspaceCompletion<SkillsWorkspaceSnapshot>? completion;
  final Object? error;
  final requests = <AppSettings>[];

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> reconfigureAgentCatalog(
    AppSettings nextSettings,
  ) async {
    events.add('reconfigure:${nextSettings.localePreference.name}');
    requests.add(nextSettings);
    if (error case final failure?) throw failure;
    return completion ??
        WorkspaceCompleted(value: SkillsWorkspaceSnapshot.empty());
  }
}
