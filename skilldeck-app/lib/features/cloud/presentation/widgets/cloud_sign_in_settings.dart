import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
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

    AppButton button(
      String label,
      VoidCallback callback, {
      bool primary = false,
    }) => AppButton(
      label: label,
      size: NeoButtonSize.small,
      style: primary ? NeoButtonVariant.primary : NeoButtonVariant.secondary,
      onPressed: callback,
    );

    final (title, description, action, additionalAction) = switch (phase) {
      null => (l10n.cloudAccount, l10n.cloudCheckingSession, null, null),
      CloudSignInPhase.signedOut => (
        l10n.cloudAccount,
        l10n.cloudSignedOut,
        button(l10n.cloudSignIn, vm.startSignIn, primary: true),
        null,
      ),
      CloudSignInPhase.starting => (
        l10n.cloudAccount,
        l10n.cloudRequestingCode,
        null,
        null,
      ),
      CloudSignInPhase.waiting => (
        l10n.cloudVerificationCode(state!.userCode!),
        state.browserOpenFailed
            ? l10n.cloudBrowserOpenFailed
            : l10n.cloudVerifyInBrowser,
        button(l10n.cloudOpenBrowser, vm.openVerificationPage, primary: true),
        button(l10n.commonCancel, vm.cancelSignIn),
      ),
      CloudSignInPhase.denied ||
      CloudSignInPhase.expired ||
      CloudSignInPhase.failed => (
        l10n.cloudAccount,
        switch (phase) {
          CloudSignInPhase.denied => l10n.cloudSignInDenied,
          CloudSignInPhase.expired => l10n.cloudSignInExpired,
          _ => l10n.cloudSignInFailed,
        },
        button(l10n.cloudTryAgain, vm.startSignIn, primary: true),
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
        null,
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
