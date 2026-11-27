import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

final _hiddenNameProvider = FutureProvider.autoDispose
    .family<String?, ({CloudSyncRuntime runtime, String lineageId})>((
      ref,
      entry,
    ) async {
      final result = await entry.runtime.runAction((reconciler) async {
        final result = await reconciler.api.readLineage(entry.lineageId);
        return switch (result) {
          CloudApiSuccess<Lineage>(:final value) => value.head?.declaredName,
          ApiSignInRequired() => const SyncAccountCondition(
            ApiSignInRequired(),
          ),
          _ => null,
        };
      });
      return result is String ? result : null;
    });

final class CloudDeviceExclusions extends ConsumerWidget {
  const CloudDeviceExclusions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(cloudSyncRuntimeProvider);
    final state = ref.watch(cloudSyncStateProvider).value;
    if (runtime == null ||
        state?.accountId != runtime.accountId ||
        state!.exclusions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSectionHeader(title: context.l10n.cloudHiddenSkills),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            children: [
              for (final lineageId in state.exclusions)
                _HiddenSkillRow(runtime: runtime, lineageId: lineageId),
            ],
          ),
        ],
      ),
    );
  }
}

final class _HiddenSkillRow extends ConsumerWidget {
  const _HiddenSkillRow({required this.runtime, required this.lineageId});
  final CloudSyncRuntime runtime;
  final String lineageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
        .watch(_hiddenNameProvider((runtime: runtime, lineageId: lineageId)))
        .value;
    return SettingsRow(
      title: name ?? context.l10n.cloudHiddenUnnamedSkill,
      trailing: AppButton(
        key: Key('cloud-include-$lineageId'),
        label: context.l10n.cloudShowAgain,
        size: NeoButtonSize.small,
        onPressed: () => unawaited(_include()),
      ),
    );
  }

  Future<void> _include() async {
    try {
      await runtime.runAction((reconciler) => reconciler.include(lineageId));
      runtime.onForeground();
    } on Object {
      // The stopped notice already explains why no action can run.
    }
  }
}
