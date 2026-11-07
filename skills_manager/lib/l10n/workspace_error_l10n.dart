import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';

String localizeWorkspaceError(
  AppLocalizations l10n,
  WorkspaceException error,
) => localizeAppFailure(l10n, error);
