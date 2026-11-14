// flutter test --no-pub -d macos \
//   --dart-define=SKILLDECK_SOURCE_COPY_ACCEPTANCE=true \
//   integration_test/source_copy_acceptance_test.dart
// Uses synthetic addresses only; never opens a browser or directory.
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_source_link.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('SKILLDECK_SOURCE_COPY_ACCEPTANCE');

  testWidgets(
    'all source categories copy their exact addresses to the native clipboard',
    (tester) async {
      final previous = await Clipboard.getData(Clipboard.kTextPlain);
      addTearDown(() async {
        if (previous != null) await Clipboard.setData(previous);
      });
      var pointer = 100;
      for (final (kind, address) in [
        (WorkspaceSourceKind.git, 'https://example.invalid/skills'),
        (WorkspaceSourceKind.git, 'git@github.com:owner/repo.git'),
        (WorkspaceSourceKind.git, 'ssh://git@github.com/owner/repo.git'),
        (WorkspaceSourceKind.local, '/tmp/我的 skills:100%'),
        (WorkspaceSourceKind.adoptedSnapshot, 'adopted:opaque path 50%'),
        (
          WorkspaceSourceKind.wellKnown,
          'https://demo:synthetic-password@example.invalid/skills?token=synthetic-token#private',
        ),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            child: CupertinoApp(
              theme: SkillsTheme.theme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: NeoButtonTheme(
                data: SkillsButtonTheme.neo,
                child: CupertinoPageScaffold(
                  child: Center(
                    child: SizedBox(
                      width: 900,
                      child: SkillSourceLinkValue(
                        source: SkillSourceProvenance(
                          kind: kind,
                          locator: address,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('skill-source-link')),
          pointer: pointer++,
        );
        await tester.pumpAndSettle();
        final copied = await Clipboard.getData(Clipboard.kTextPlain);
        expect(
          copied?.text == address,
          isTrue,
          reason: 'Native clipboard must preserve the original source address.',
        );
        expect(find.textContaining('synthetic-password'), findsNothing);
        expect(find.textContaining('synthetic-token'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !enabled || !Platform.isMacOS,
  );
}
