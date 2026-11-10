import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';

String localizeAcquisitionFailure(
  AppLocalizations l10n,
  SkillAcquisitionOperation operation,
) => switch (operation) {
  SkillAcquisitionOperation.resolveSource => l10n.acquisitionErrorResolve,
  SkillAcquisitionOperation.inspectSource => l10n.acquisitionErrorInspect,
  SkillAcquisitionOperation.installSkills => l10n.acquisitionErrorInstall,
  SkillAcquisitionOperation.confirmInstallTakeover =>
    l10n.acquisitionErrorInstall,
  SkillAcquisitionOperation.refreshAfterInstall => l10n.acquisitionErrorRefresh,
};
