// Opt in on a macOS desktop with a configured default browser:
// flutter test --no-pub -d macos \
//   --dart-define=SKILLDECK_SOURCE_LINK_ACCEPTANCE=true \
//   integration_test/source_link_browser_acceptance_test.dart
// Opens one temporary loopback page; never opens the user's Workspace.
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
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
  const enabled = bool.fromEnvironment('SKILLDECK_SOURCE_LINK_ACCEPTANCE');

  testWidgets('a source click opens the actual default browser', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<void>();
    const path = '/skilldeck-source-acceptance';
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>SkillDeck source test</title>Source link accepted.',
      );
      await request.response.close();
      if (request.method == 'GET' &&
          request.uri.path == path &&
          !requested.isCompleted) {
        requested.complete();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final locator = 'http://127.0.0.1:${server.port}$path';
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          theme: SkillsTheme.theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 600,
                  child: SkillSourceLinkValue(
                    source: SkillSourceProvenance(
                      kind: WorkspaceSourceKind.git,
                      locator: locator,
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
    await tester.tap(find.byKey(const Key('skill-source-link')));
    await tester.runAsync(
      () => requested.future.timeout(const Duration(seconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-source-link-failed')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !enabled || !Platform.isMacOS);
}
