import 'package:flutter/widgets.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';

export 'generated/app_localizations.dart';

const Locale defaultAppLocale = Locale('zh');

AppLocalizations appLocalizationsFor(Locale locale) =>
    lookupAppLocalizations(locale);

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
