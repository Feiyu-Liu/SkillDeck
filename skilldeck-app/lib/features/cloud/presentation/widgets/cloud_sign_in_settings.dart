import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/presentation/view_models/cloud_sign_in_view_model.dart';
import 'package:skills_manager/features/cloud/presentation/widgets/cloud_device_exclusions.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class CloudSignInSettings extends ConsumerWidget {
  const CloudSignInSettings({required this.showSectionHeader, super.key});

  final bool showSectionHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudOriginProvider) == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final state = ref.watch(cloudSignInViewModelProvider).value;
    final vm = ref.read(cloudSignInViewModelProvider.notifier);
    final email = state?.account?.email;
    final phase = state?.phase;
    final metadataUnavailable =
        phase == CloudSignInPhase.signedIn &&
        ref.watch(
          cloudSyncStateProvider.select(
            (sync) =>
                sync.value?.accountId == state?.account?.id &&
                sync.value?.metadataUnavailable == true,
          ),
        );

    AppButton button(
      String label,
      VoidCallback callback, {
      bool primary = false,
      bool loading = false,
    }) => AppButton(
      label: label,
      size: NeoButtonSize.small,
      style: primary ? NeoButtonVariant.primary : NeoButtonVariant.secondary,
      onPressed: callback,
      loading: loading,
    );

    final (title, description, action, additionalAction) = switch (phase) {
      null => (l10n.cloudAccount, l10n.cloudCheckingSession, null, null),
      CloudSignInPhase.signedOut => (
        l10n.cloudAccount,
        l10n.cloudSignedOut,
        button(l10n.cloudSignIn, vm.startSignIn, primary: true),
        null,
      ),
      CloudSignInPhase.signingIn => (
        l10n.cloudAccount,
        l10n.cloudSigningIn,
        button(l10n.cloudSignIn, vm.startSignIn, primary: true, loading: true),
        null,
      ),
      CloudSignInPhase.failed => (
        l10n.cloudAccount,
        switch (state?.failure) {
          CloudSignInFailure.network => l10n.cloudSignInNetworkFailed,
          CloudSignInFailure.busy => l10n.cloudSignInBusy,
          _ => l10n.cloudSignInOtherFailed,
        },
        button(l10n.cloudSignIn, vm.startSignIn, primary: true),
        null,
      ),
      CloudSignInPhase.sessionCheckFailed => (
        l10n.cloudAccount,
        l10n.cloudSessionCheckFailed,
        button(l10n.cloudTryAgain, vm.refreshSession, primary: true),
        null,
      ),
      CloudSignInPhase.offline => (
        email ?? l10n.cloudAccount,
        l10n.cloudOffline,
        button(l10n.cloudTryAgain, vm.refreshSession),
        button(l10n.cloudSignOut, vm.signOut),
      ),
      CloudSignInPhase.signedIn => (
        email ?? l10n.cloudAccount,
        metadataUnavailable ? l10n.cloudMetadataUnavailable : null,
        button(l10n.cloudSignOut, vm.signOut),
        null,
      ),
      CloudSignInPhase.signingOut => (
        email ?? l10n.cloudAccount,
        l10n.cloudSigningOut,
        null,
        null,
      ),
      CloudSignInPhase.signOutFailed => (
        email ?? l10n.cloudAccount,
        l10n.cloudSignOutFailed,
        button(l10n.cloudSignOut, vm.signOut),
        null,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSectionHeader) ...[
          SettingsSectionHeader(title: l10n.cloudSettingsTitle),
          const SizedBox(height: AppSpacing.xl),
        ],
        SettingsGroup(
          children: [
            SettingsRow(
              title: title,
              description: description,
              trailing: additionalAction == null
                  ? action
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [action!, additionalAction],
                    ),
            ),
          ],
        ),
        if (state?.verifiedAccount != null) const CloudDeviceExclusions(),
      ],
    );
  }
}
