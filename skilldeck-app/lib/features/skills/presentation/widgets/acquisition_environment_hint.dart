import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';

/// Shown when a source cannot be prepared because the host is not set up yet.
///
/// Keyed off the typed failure alone, never off the kind of source, so the
/// acquisition flow stays source-agnostic. It only points at the Environment
/// check section; all remediation guidance lives there, in one place.
class AcquisitionEnvironmentHint extends StatelessWidget {
  const AcquisitionEnvironmentHint({required this.failure, super.key});

  final AppFailure failure;

  @override
  Widget build(BuildContext context) => AppFailureView(
    failure: failure,
    variant: AppFailureViewVariant.banner,
    actionLabel: context.l10n.acquisitionGoToEnvironmentSettings,
    actionKey: const Key('acquisition-environment-settings'),
    actionIcon: LucideIcons.settings,
    onAction: () {
      // Resolve the router before popping: afterwards this context is
      // deactivated and cannot look one up.
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go(settingsLocation(SettingsSection.maintenance));
    },
  );
}
