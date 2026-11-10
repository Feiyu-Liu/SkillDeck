import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/presentation/widgets/environment_check_settings.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  testWidgets('shows an unchecked host without touching it', (tester) async {
    // The probe raises the operating system's install dialog on an affected
    // macOS host, so merely opening this section must never run it.
    final repository = FakeSkillsWorkspaceRepository();
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Not checked yet'), findsOneWidget);
    expect(repository.gitEnvironmentProbeCount, isZero);
  });

  testWidgets('reports an available Git after an explicit check', (
    tester,
  ) async {
    final repository = FakeSkillsWorkspaceRepository()
      ..gitEnvironmentGate = Completer<void>();
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('environment-check-recheck')));
    await tester.pump();
    expect(find.text('Checking…'), findsOneWidget);

    repository.gitEnvironmentGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Git is available.'), findsOneWidget);
    expect(repository.gitEnvironmentProbeCount, 1);
  });

  testWidgets('gives each host outcome its own wording', (tester) async {
    const expectations = <WorkspaceGitEnvironmentStatus, String>{
      WorkspaceGitEnvironmentStatus.notInstalled:
          'Git was not found on this device. Public HTTPS repositories still '
          'install; SSH and private repositories need Git.',
      WorkspaceGitEnvironmentStatus.developerToolsRequired:
          'The macOS Command Line Developer Tools are required. Choose Install '
          'in the system dialog, then recheck.',
      WorkspaceGitEnvironmentStatus.developerToolsInstalling:
          'The Command Line Developer Tools are installing. Recheck once the '
          'install finishes.',
      WorkspaceGitEnvironmentStatus.probeFailed:
          'The Git check did not complete.',
    };
    for (final entry in expectations.entries) {
      final repository = FakeSkillsWorkspaceRepository()
        ..gitEnvironmentStatus = entry.key;
      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('environment-check-recheck')));
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
    }
  });

  testWidgets('treats a thrown probe as a failed check', (tester) async {
    final repository = FakeSkillsWorkspaceRepository()
      ..gitEnvironmentError = StateError('boom');
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('environment-check-recheck')));
    await tester.pumpAndSettle();

    expect(find.text('The Git check did not complete.'), findsOneWidget);
  });

  testWidgets('offers reopening the install prompt only when it can help', (
    tester,
  ) async {
    final repository = FakeSkillsWorkspaceRepository();
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('environment-check-recheck')));
    await tester.pumpAndSettle();

    const promptKey = Key('environment-check-open-install-prompt');
    expect(find.byKey(promptKey), findsNothing);

    repository.gitEnvironmentStatus =
        WorkspaceGitEnvironmentStatus.developerToolsRequired;
    await tester.tap(find.byKey(const Key('environment-check-recheck')));
    await tester.pumpAndSettle();

    if (!Platform.isMacOS) {
      // No operating system dialog exists to reopen elsewhere.
      expect(find.byKey(promptKey), findsNothing);
      return;
    }
    expect(find.byKey(promptKey), findsOneWidget);

    // Re-running the probe is exactly what re-raises the dialog for a user who
    // dismissed it.
    await tester.tap(find.byKey(promptKey));
    await tester.pumpAndSettle();
    expect(repository.gitEnvironmentProbeCount, 3);
  });
}

Widget _testApp(FakeSkillsWorkspaceRepository repository) => ProviderScope(
  overrides: [skillsWorkspaceRepositoryProvider.overrideWithValue(repository)],
  child: CupertinoApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: SkillsTheme.theme,
    home: const CupertinoPageScaffold(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: EnvironmentCheckSettings(),
      ),
    ),
  ),
);
