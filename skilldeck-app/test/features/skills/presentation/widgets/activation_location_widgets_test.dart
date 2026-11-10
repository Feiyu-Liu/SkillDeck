import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';

Widget host(Widget child, {Locale locale = const Locale('en')}) => CupertinoApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: CupertinoPageScaffold(
    child: Center(child: SizedBox(width: 360, child: child)),
  ),
);

WorkspaceActivationTarget target(
  String id,
  String location, {
  bool detected = true,
}) => WorkspaceActivationTarget(
  agentId: id,
  displayName: id,
  location: location,
  scope: WorkspaceScope.global,
  detected: detected,
);

void main() {
  for (final (locale, label) in [
    (const Locale('en'), 'Universal Agents'),
    (const Locale('zh'), '通用 Agents'),
  ]) {
    testWidgets('Universal Agents has one identity in $locale', (tester) async {
      final group = groupActivationLocations([
        target('codex', '/shared'),
        target('opencode', '/shared'),
        target('universal', '/shared', detected: false),
      ]).single;
      await tester.pumpWidget(
        host(AgentActivationGroupLabel(group: group), locale: locale),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text('/shared'), findsOneWidget);
      expect(find.text('Universal'), findsNothing);
      expect(find.byKey(const Key('agent-logo-codex')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('non-Universal Agent does not repeat its icon below the path', (
    tester,
  ) async {
    final group = ActivationLocationGroup([target('claude-code', '/claude')]);
    await tester.pumpWidget(host(AgentActivationGroupLabel(group: group)));
    await tester.pumpAndSettle();
    expect(find.text('claude-code'), findsOneWidget);
    expect(find.byKey(const Key('agent-logo-stack')), findsNothing);
    expect(find.byKey(const Key('agent-logo-claude-code')), findsOneWidget);
  });

  testWidgets('long path fits and is available on hover', (tester) async {
    final path = '/home/${'long-segment/' * 25}/skills';
    await tester.pumpWidget(
      host(
        AgentActivationGroupLabel(
          group: ActivationLocationGroup([target('custom', path)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text(path)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(path), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });
}
