import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_source_link.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';
import 'package:skills_manager/shared/notifications/toastification_app_notification_presenter.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_notification_host.dart';
import 'package:skills_manager/shared/widgets/app_notification_toast.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  setUp(
    () => messenger.setMockMethodCallHandler(
      launcher,
      (_) async => fail('A source click must never launch a URL or directory.'),
    ),
  );
  tearDown(() {
    messenger.setMockMethodCallHandler(launcher, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  void clipboard(Future<Object?> Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(SystemChannels.platform, handler);

  Future<void> pumpPanel(
    WidgetTester tester,
    AppNotificationPresenter presenter,
  ) async {
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          InstalledSkill(
            id: WorkspaceSkillId('alpha'),
            description: 'Alpha',
            contentHash: 'hash-alpha',
            activationCount: 0,
            slotKey: 'alpha',
            displayName: 'Alpha',
            source: const SkillSourceProvenance(
              kind: WorkspaceSourceKind.local,
              locator: '/tmp/my skills:100%',
            ),
          ),
        ],
      ),
      documents: const {'alpha': '# Alpha'},
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        notificationPresenter: presenter,
        initialLocation: '/installed/alpha/activate',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'every source category copies the exact address and shows a generic floating notification',
    (tester) async {
      final copied = <String>[];
      clipboard((call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      final presenter = _RecordingPresenter();
      final sources = [
        (
          WorkspaceSourceKind.git,
          'https://github.com/owner/repo?tab=readme-ov-file#readme',
        ),
        (WorkspaceSourceKind.wellKnown, 'https://example.com/skills'),
        (WorkspaceSourceKind.git, 'git@github.com:owner/repo.git'),
        (WorkspaceSourceKind.git, 'ssh://git@github.com/owner/repo.git'),
        (WorkspaceSourceKind.local, '/tmp/my skills:100%'),
        (WorkspaceSourceKind.adoptedSnapshot, 'adopted:opaque path 50%'),
        (
          WorkspaceSourceKind.git,
          'https://user:password@example.com/repo?token=secret#private',
        ),
      ];
      for (final (kind, address) in sources) {
        await tester.pumpWidget(
          _fixture(
            presenter,
            SkillSourceProvenance(kind: kind, locator: ' $address '),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('skill-source-link')));
        await tester.pumpAndSettle();
        expect(copied.last, address);
        final notification = presenter.presentations.last;
        expect(notification.kind, AppNotificationPresentationKind.transient);
        expect(notification.content.severity, AppNotificationSeverity.success);
        expect(notification.content.message, 'Source address copied.');
        expect(notification.content.copyText, isNull);
        expect(notification.content.detail, isNull);
        expect(find.text('Source address copied.'), findsNothing);
      }
      expect(copied, sources.map((source) => source.$2));
      expect(presenter.presentations, hasLength(sources.length));
    },
  );

  for (final succeeds in [true, false]) {
    testWidgets(
      'floating ${succeeds ? 'success' : 'failure'} keeps the metadata card and badge geometry fixed',
      (tester) async {
        final pending = Completer<Object?>();
        clipboard((call) async {
          if (call.method == 'Clipboard.setData') return pending.future;
          return null;
        });
        final presenter = ToastificationAppNotificationPresenter();
        addTearDown(presenter.dispose);
        await pumpPanel(tester, presenter);
        final source = find.byKey(const Key('skill-source-meta'));
        final card = find
            .ancestor(of: source, matching: find.byType(Container))
            .first;
        final measured = [
          source,
          card,
          find.byKey(const Key('skill-version-meta')),
          find.byKey(const Key('skill-source-kind-tag')),
          find.byKey(const Key('skill-source-link')),
        ];
        final before = measured.map(tester.getRect).toList();
        await tester.tap(find.byKey(const Key('skill-source-link')));
        await tester.pump();
        expect(measured.map(tester.getRect).toList(), before);
        if (succeeds) {
          pending.complete(null);
        } else {
          pending.completeError(
            PlatformException(
              code: 'failed',
              message: 'private clipboard data',
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AppNotificationToast), findsOneWidget);
        expect(
          find.text(
            succeeds
                ? 'Source address copied.'
                : 'The source address could not be copied.',
          ),
          findsOneWidget,
        );
        expect(measured.map(tester.getRect).toList(), before);
        expect(
          find
              .descendant(of: source, matching: find.byType(Text))
              .evaluate()
              .map((element) => (element.widget as Text).data)
              .join(),
          isNot(contains('copied')),
        );
        presenter.dismissAll();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'credentials stay out of visible text, tooltip, semantics and notifications',
    (tester) async {
      clipboard((_) async => null);
      final presenter = _RecordingPresenter();
      await tester.pumpWidget(
        _fixture(
          presenter,
          const SkillSourceProvenance(
            kind: WorkspaceSourceKind.git,
            locator:
                'https://user:password@example.com/repo?token=secret#private',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppTooltip>(find.byType(AppTooltip)).message,
        'Copy source: https://example.com/repo',
      );
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Copy source: https://example.com/repo'),
        findsOneWidget,
      );
      semantics.dispose();
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join();
      expect(texts, isNot(contains('password')));
      expect(texts, isNot(contains('secret')));
      expect(
        presenter.presentations.single.content.message,
        'Source address copied.',
      );
    },
  );

  testWidgets('source copy supports keyboard activation', (tester) async {
    String? copied;
    clipboard((call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(
      _fixture(
        _RecordingPresenter(),
        const SkillSourceProvenance(
          kind: WorkspaceSourceKind.git,
          locator: 'https://example.com/repo',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = find
        .descendant(
          of: find.byKey(const Key('skill-source-link')),
          matching: find.byType(Text),
        )
        .first;
    Focus.of(tester.element(label)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(copied, 'https://example.com/repo');
  });

  testWidgets('missing and empty sources have no copy button', (tester) async {
    for (final source in [
      null,
      const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: ' ',
      ),
    ]) {
      await tester.pumpWidget(_fixture(_RecordingPresenter(), source));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-source-link')), findsNothing);
      expect(find.text('Source address unavailable'), findsOneWidget);
    }
  });

  testWidgets(
    'duplicate clicks and disposed completions do not publish feedback',
    (tester) async {
      final pending = Completer<Object?>();
      var copies = 0;
      clipboard((call) async {
        if (call.method == 'Clipboard.setData') {
          copies++;
          return pending.future;
        }
        return null;
      });
      final presenter = _RecordingPresenter();
      await tester.pumpWidget(
        _fixture(
          presenter,
          const SkillSourceProvenance(
            kind: WorkspaceSourceKind.git,
            locator: 'ssh://git@example.com/repo',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.tap(find.byKey(const Key('skill-source-link')));
      expect(copies, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(presenter.presentations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a replacement source suppresses stale feedback and permits copying again',
    (tester) async {
      final old = Completer<Object?>();
      clipboard((call) async {
        if (call.method == 'Clipboard.setData' &&
            (call.arguments as Map)['text'] == 'old') {
          return old.future;
        }
        return null;
      });
      final presenter = _RecordingPresenter();
      await tester.pumpWidget(
        _fixture(
          presenter,
          const SkillSourceProvenance(
            kind: WorkspaceSourceKind.local,
            locator: 'old',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.pumpWidget(
        _fixture(
          presenter,
          const SkillSourceProvenance(
            kind: WorkspaceSourceKind.local,
            locator: 'new',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.pumpAndSettle();
      old.complete(null);
      await tester.pumpAndSettle();
      expect(presenter.presentations, hasLength(1));
      expect(find.text('new'), findsOneWidget);
    },
  );
}

Widget _fixture(
  AppNotificationPresenter presenter,
  SkillSourceProvenance? source,
) => ProviderScope(
  overrides: [appNotificationPresenterProvider.overrideWithValue(presenter)],
  child: CupertinoApp(
    theme: SkillsTheme.theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: NeoButtonTheme(
      data: SkillsButtonTheme.neo,
      child: AppNotificationHost(
        child: CupertinoPageScaffold(
          child: Center(
            child: SizedBox(
              width: 600,
              child: SkillSourceLinkValue(source: source),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _RecordingPresenter implements AppNotificationPresenter {
  final presentations = <AppNotificationPresentation>[];
  @override
  void present(AppNotificationPresentation presentation) =>
      presentations.add(presentation);
  @override
  void dismissAll() {}
  @override
  void dispose() {}
}
