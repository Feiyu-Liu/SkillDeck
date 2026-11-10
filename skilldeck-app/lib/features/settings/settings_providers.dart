import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/presentation/view_models/external_skills_view_model.dart';
import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/data/app_settings_coordinator.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/presentation/view_models/app_settings_view_model.dart';
import 'package:skills_manager/features/settings/presentation/view_models/environment_check_view_model.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

final appSettingsStoreProvider = Provider<AppSettingsStore>((ref) {
  return SharedPreferencesAppSettingsStore();
});

final skillsManagerRuntimeFactoryProvider =
    Provider<SkillsManagerRuntime Function()>((ref) {
      throw UnimplementedError('A SkillsManagerRuntime factory is required.');
    });

/// Root Provider-container owner of the process-lifetime Workspace runtime.
///
/// Features borrow repositories from this Runtime. Disposing the root
/// container closes the Runtime exactly once through its idempotent close.
final skillsManagerRuntimeProvider = Provider<SkillsManagerRuntime>((ref) {
  final runtime = ref.watch(skillsManagerRuntimeFactoryProvider)();
  final diagnostics = ref.watch(appDiagnosticsProvider);
  ref.onDispose(
    () => unawaited(_closeRuntime(runtime: runtime, diagnostics: diagnostics)),
  );
  return runtime;
});

Future<void> _closeRuntime({
  required SkillsManagerRuntime runtime,
  required AppDiagnostics diagnostics,
}) async {
  try {
    await runtime.close();
  } on Object catch (error, stackTrace) {
    diagnostics.unhandled(
      error: error,
      operationKey: 'shutdownWorkspace',
      stackTrace: stackTrace,
    );
  }
}

final appSettingsRuntimeProvider = Provider<AppSettingsRuntime>((ref) {
  return ref.watch(skillsManagerRuntimeProvider);
});

final appSettingsCoordinatorProvider = Provider<AppSettingsCoordinator>((ref) {
  return AppSettingsCoordinator(
    store: ref.watch(appSettingsStoreProvider),
    runtime: ref.watch(appSettingsRuntimeProvider),
    onCommittedPending: (pending) => ref
        .read(workspaceFinalizationCoordinatorProvider.notifier)
        .register(pending),
    onCatalogReconfigured: () {
      ref.invalidate(agentRootOwnershipCoordinatorProvider);
      ref.read(activationCatalogRevisionProvider.notifier).refresh();
      ref.read(externalSkillsViewModelProvider.notifier).agentCatalogChanged();
    },
  );
});

final appSettingsViewModelProvider =
    NotifierProvider<AppSettingsViewModel, AppSettingsState>(
      AppSettingsViewModel.new,
    );

/// The user's method for new global Activations. Requests that create
/// Activations read it at submission time; the repository seam decides where
/// it applies.
final globalActivationMethodProvider = Provider<WorkspaceActivationMethod>(
  (ref) => ref.watch(
    appSettingsViewModelProvider.select(
      (state) => state.settings.globalActivationMethod,
    ),
  ),
);

final environmentCheckViewModelProvider =
    NotifierProvider<EnvironmentCheckViewModel, EnvironmentCheckState>(
      EnvironmentCheckViewModel.new,
    );
