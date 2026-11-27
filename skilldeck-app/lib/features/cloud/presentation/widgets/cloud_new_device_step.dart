import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/app/app_router.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_takeover_dialog.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

typedef _ActivationSelection =
    Map<WorkspaceSkillId, List<ActivationLocationGroup>>;

final class CloudNewDeviceStep extends ConsumerStatefulWidget {
  const CloudNewDeviceStep({super.key});

  @override
  ConsumerState<CloudNewDeviceStep> createState() => _CloudNewDeviceStepState();
}

final class _CloudNewDeviceStepState extends ConsumerState<CloudNewDeviceStep> {
  final Set<String> _offered = {};

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(cloudSyncRuntimeProvider);
    final state = ref.watch(cloudSyncStateProvider).value;
    if (runtime != null &&
        state?.accountId == runtime.accountId &&
        state!.bootstrapCompleted &&
        state.installedSkillIds.isNotEmpty) {
      if (_offered.add(runtime.accountId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_show(runtime, state.installedSkillIds));
        });
      }
    }
    return const SizedBox.shrink();
  }

  Future<void> _show(CloudSyncRuntime runtime, Set<String> ids) async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null || !_current(runtime)) return;
    if (!await ref.read(claimCloudActivationOfferProvider)(runtime.accountId) ||
        !mounted ||
        !_current(runtime)) {
      return;
    }
    final selection = await navigator.push<_ActivationSelection>(
      AppDialogMotion.route(
        barrierDismissible: true,
        barrierColor: AppPalette.of(context).modalScrim,
        builder: (context) => _CloudNewDeviceDialog(installedIds: ids),
      ),
    );
    if (selection == null || !_current(runtime)) return;
    final operations = ref.read(skillOperationsViewModelProvider.notifier);
    try {
      await runtime.runAction((_) async {
        for (final entry in selection.entries) {
          if (!_current(runtime)) return;
          final groups = entry.value;
          await operations.setActivation(
            skillId: entry.key,
            target: groups.first.first,
            active: true,
            agentIds: {for (final group in groups) ...group.requestAgentIds},
            locations: {for (final group in groups) group.first.location},
            onTakeoverRequired: (draft) async {
              final overlay = navigator.overlay?.context;
              if (!_current(runtime) || overlay == null) return false;
              return showActivationTakeoverDialog(
                context: overlay,
                draft: draft,
                agentName: groups
                    .map((group) => activationAgentGroupTitle(overlay, group))
                    .join(', '),
              );
            },
          );
        }
      });
    } on Object {
      // The existing Activation flow reports action failures.
    }
  }

  bool _current(CloudSyncRuntime runtime) =>
      mounted && identical(ref.read(cloudSyncRuntimeProvider), runtime);
}

final class _CloudNewDeviceDialog extends ConsumerStatefulWidget {
  const _CloudNewDeviceDialog({required this.installedIds});
  final Set<String> installedIds;

  @override
  ConsumerState<_CloudNewDeviceDialog> createState() =>
      _CloudNewDeviceDialogState();
}

final class _CloudNewDeviceDialogState
    extends ConsumerState<_CloudNewDeviceDialog> {
  final _chosen = <WorkspaceSkillId, Set<ActivationLocationKey>>{};

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(workspaceSkillsProvider).value ?? [];
    final skills = snapshot.where(
      (skill) => widget.installedIds.contains(skill.id.value),
    );
    final targets = ref.watch(
      activationTargetsProvider((
        scope: WorkspaceScope.global,
        projectRootId: null,
      )),
    );
    final members = ref.watch(deviceAgentMembersProvider).value ?? const {};
    final groups = switch (targets.value) {
      WorkspaceCompleted<List<WorkspaceActivationTarget>>(:final value) =>
        deviceActivationGroups(
          value,
          members,
        ).where((group) => group.canActivate).toList(),
      _ => <ActivationLocationGroup>[],
    };
    final selection = <WorkspaceSkillId, List<ActivationLocationGroup>>{
      for (final skill in skills)
        if (_chosen[skill.id]?.isNotEmpty ?? false)
          skill.id: groups
              .where((group) => _chosen[skill.id]!.contains(group.key))
              .toList(),
    }..removeWhere((_, selected) => selected.isEmpty);
    final l10n = context.l10n;
    return AppDialogScaffold(
      width: 510,
      onEscape: () => Navigator.pop(context),
      header: AppDialogHeader(
        title: l10n.cloudNewDeviceTitle,
        subtitle: l10n.cloudNewDeviceSubtitle,
        icon: LucideIcons.cloudDownload,
      ),
      sections: [
        if (groups.isEmpty)
          AppDialogSection(
            child: Text(
              targets.isLoading
                  ? l10n.cloudActivationLoading
                  : l10n.workspaceActivateNoTargets,
            ),
          ),
        for (final skill in skills)
          AppDialogSection(
            title: skill.displayName,
            child: Column(
              children: [
                for (final group in groups)
                  Row(
                    children: [
                      Semantics(
                        label:
                            '${skill.displayName} ${activationAgentGroupTitle(context, group)}',
                        child: CupertinoCheckbox(
                          value:
                              _chosen[skill.id]?.contains(group.key) ?? false,
                          onChanged: (selected) => setState(() {
                            final selectedGroups = _chosen.putIfAbsent(
                              skill.id,
                              () => {},
                            );
                            if (selected == true) {
                              selectedGroups.add(group.key);
                            } else {
                              selectedGroups.remove(group.key);
                            }
                          }),
                        ),
                      ),
                      Expanded(child: AgentActivationGroupLabel(group: group)),
                    ],
                  ),
              ],
            ),
          ),
      ],
      footer: AppDialogFooter(
        actions: [
          AppButton(
            key: const Key('cloud-new-device-later'),
            label: l10n.cloudActivateLater,
            onPressed: () => Navigator.pop(context),
          ),
          AppButton(
            key: const Key('cloud-new-device-activate'),
            label: l10n.cloudActivateSelected,
            style: NeoButtonVariant.primary,
            onPressed: selection.isEmpty
                ? null
                : () => Navigator.pop(context, selection),
          ),
        ],
      ),
    );
  }
}
