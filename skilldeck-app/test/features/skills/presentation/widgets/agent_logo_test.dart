import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo_registry.dart';

void main() {
  for (final entry in {
    'grok': 'grok',
    'minimax-code': 'minimax',
    'deepseek-harness': 'deepseek',
    'workbuddy': 'workbuddy',
  }.entries) {
    for (final brandColor in [true, false]) {
      testWidgets('${entry.key} renders its Lobe icon (color=$brandColor)', (
        tester,
      ) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: Center(
              child: AgentLogo(agentId: entry.key, useBrandColor: brandColor),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final colored = brandColor && entry.key != 'grok';
        if (entry.key == 'workbuddy' && colored) {
          final image = tester.widget<Image>(find.byType(Image));
          expect(
            (image.image as AssetImage).assetName,
            'assets/agent_icons/workbuddy-color.png',
          );
          expect(find.byType(SvgPicture), findsNothing);
          expect(tester.takeException(), isNull);
          return;
        }
        final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(
          (picture.bytesLoader as SvgAssetLoader).assetName,
          'assets/agent_icons/${entry.value}${colored ? '-color' : ''}.svg',
        );
        expect(picture.colorFilter, colored ? isNull : isNotNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final id in ['kimchi', 'posit-assistant', 'fx', 'sarvam-code']) {
    testWidgets('$id uses neutral fallback', (tester) async {
      await tester.pumpWidget(CupertinoApp(home: AgentLogo(agentId: id)));
      expect(find.byIcon(LucideIcons.bot), findsOneWidget);
    });
  }

  testWidgets('renders a curated SVG for a mapped Agent', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(child: AgentLogo(agentId: 'codex')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-logo-codex')), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(LucideIcons.bot), findsNothing);
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      'assets/agent_icons/codex-color.svg',
    );
    expect(picture.colorFilter, isNull);
  });

  testWidgets('uses a white-tintable monochrome asset when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: AgentLogo(
            agentId: 'codex',
            color: CupertinoColors.white,
            useBrandColor: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      'assets/agent_icons/codex.svg',
    );
    expect(picture.colorFilter, isNotNull);
  });

  testWidgets('uses the compatible raster color asset when SVG filters exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(child: AgentLogo(agentId: 'antigravity')),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/agent_icons/antigravity-color.png',
    );
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('renders the neutral fallback for an unmapped Agent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(child: AgentLogo(agentId: 'custom-agent')),
      ),
    );

    expect(find.byKey(const Key('agent-logo-custom-agent')), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byIcon(LucideIcons.bot), findsOneWidget);
  });

  testWidgets('parses every curated color asset', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Wrap(
          children: [
            for (final agentId in AgentLogoRegistry.assetSlugs.keys)
              AgentLogo(agentId: agentId),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(33));
    expect(find.byType(Image), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deduplicates grouped Agents and summarizes overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: AgentLogoStack(
            agentIds: ['codex', 'claude-code', 'codex', 'cursor', 'warp'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-logo-stack')), findsOneWidget);
    expect(find.byKey(const Key('agent-logo-codex')), findsOneWidget);
    expect(find.byKey(const Key('agent-logo-claude-code')), findsOneWidget);
    expect(find.byKey(const Key('agent-logo-stack-overflow')), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });
}
