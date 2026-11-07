import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/data/custom_agent_adapter.dart';
import 'package:skills_manager/features/settings/data/app_settings_coordinator.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

enum AppSettingsStatus { loading, ready, saving, failure }

final class AppSettingsState {
  const AppSettingsState({
    this.status = AppSettingsStatus.loading,
    this.settings = const AppSettings(),
    this.errorCode,
  });

  final AppSettingsStatus status;
  final AppSettings settings;
  final String? errorCode;

  bool get isBusy => status == AppSettingsStatus.saving;

  AppSettingsState copyWith({
    AppSettingsStatus? status,
    AppSettings? settings,
    Object? errorCode = _unset,
  }) => AppSettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    errorCode: identical(errorCode, _unset)
        ? this.errorCode
        : errorCode as String?,
  );
}

const _unset = Object();

final class AppSettingsViewModel extends Notifier<AppSettingsState> {
  AppSettingsStore get _store => ref.read(appSettingsStoreProvider);
  AppSettingsCoordinator get _coordinator =>
      ref.read(appSettingsCoordinatorProvider);

  @override
  AppSettingsState build() {
    Future.microtask(() {
      if (ref.mounted) unawaited(load());
    });
    return const AppSettingsState();
  }

  Future<void> load() async {
    if (state.status == AppSettingsStatus.saving) return;
    try {
      final settings = await _store.read() ?? const AppSettings();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: AppSettingsStatus.ready,
        settings: settings,
        errorCode: null,
      );
    } on Object {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: AppSettingsStatus.failure,
        errorCode: 'settings_load_failed',
      );
    }
  }

  Future<bool> setLocalePreference(AppLocalePreference preference) async {
    return _save(
      state.settings.copyWith(localePreference: preference),
      reloadRuntime: false,
    );
  }

  Future<bool> setSuppressDuplicateActivationConfirmation(bool suppress) {
    return _save(
      state.settings.copyWith(
        suppressDuplicateActivationConfirmation: suppress,
      ),
      reloadRuntime: false,
    );
  }

  Future<bool> setSidebarCollapsed(bool collapsed) {
    return _save(
      state.settings.copyWith(sidebarCollapsed: collapsed),
      reloadRuntime: false,
    );
  }

  Future<bool> setGlobalActivationMethod(WorkspaceActivationMethod method) {
    return _save(
      state.settings.copyWith(globalActivationMethod: method),
      reloadRuntime: false,
    );
  }

  Future<bool> saveCustomAgent(CustomAgentSettings agent) async {
    if (state.isBusy || state.status == AppSettingsStatus.loading) return false;
    try {
      agent.validate();
    } on Object {
      state = state.copyWith(
        status: AppSettingsStatus.failure,
        errorCode: 'settings_invalid',
      );
      return false;
    }
    final agents = [...state.settings.customAgents];
    final index = agents.indexWhere((item) => item.id == agent.id);
    if (index == -1) {
      agents.add(agent);
    } else {
      agents[index] = agent;
    }
    try {
      validateCustomAgentIds(agents);
    } on Object {
      state = state.copyWith(
        status: AppSettingsStatus.failure,
        errorCode: 'settings_agent_id_conflict',
      );
      return false;
    }
    return _save(state.settings.copyWith(customAgents: agents));
  }

  Future<bool> deleteCustomAgent(String id) async {
    final agents = state.settings.customAgents
        .where((item) => item.id != id)
        .toList();
    return _save(state.settings.copyWith(customAgents: agents));
  }

  Future<bool> setBuiltInAgentMembership(String id, bool included) {
    if (id.isEmpty || id == 'universal' || id.startsWith('custom-')) {
      return Future.value(false);
    }
    return _save(
      state.settings.copyWith(
        builtInAgentVisibilityOverrides: {
          ...state.settings.builtInAgentVisibilityOverrides,
          id: included,
        },
      ),
      reloadRuntime: false,
    );
  }

  Future<bool> _save(AppSettings next, {bool reloadRuntime = true}) async {
    if (state.isBusy ||
        state.status == AppSettingsStatus.loading ||
        state.errorCode == 'settings_load_failed') {
      return false;
    }
    state = state.copyWith(status: AppSettingsStatus.saving, errorCode: null);
    try {
      if (reloadRuntime) {
        final completion = await _coordinator.save(next);
        if (completion case WorkspaceFailed(:final failure)) {
          if (!ref.mounted) return false;
          state = state.copyWith(
            status: AppSettingsStatus.failure,
            errorCode: _settingsErrorCode(failure),
          );
          return false;
        }
      } else {
        await _store.write(next);
      }
      if (!ref.mounted) return false;
      state = state.copyWith(status: AppSettingsStatus.ready, settings: next);
      return true;
    } on Object {
      if (!ref.mounted) return false;
      state = state.copyWith(
        status: AppSettingsStatus.failure,
        errorCode: 'settings_save_failed',
      );
      return false;
    }
  }

  String _settingsErrorCode(WorkspaceFailure failure) => switch (failure.code) {
    WorkspaceErrorCode.duplicateAgentId => 'settings_agent_id_conflict',
    WorkspaceErrorCode.invalidSource ||
    WorkspaceErrorCode.invalidProjectRoot => 'settings_invalid',
    _ => 'settings_save_failed',
  };
}
