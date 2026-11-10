import 'package:flutter/cupertino.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:smooth_corner/smooth_corner.dart';

void main() {
  testWidgets('uses the app code block typography and palette', (tester) async {
    final theme = await _markdownTheme(tester);

    expect(theme.resolvedCodeStyle.fontFamily, AppFonts.mono);
    expect(theme.resolvedCodeBackgroundColor, AppColors.surfaceMuted);
    expect(
      theme.codePadding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
    expect(theme.resolvedCodeBorderRadius, BorderRadius.circular(AppRadii.md));
    expect(theme.resolvedCodeTheme['keyword']?.color, AppColors.codeKeyword);
    expect(theme.resolvedCodeTheme['string']?.color, AppColors.codeString);
    expect(theme.codeHighlighter, isA<AppMarkdownCodeHighlighter>());
  });

  testWidgets('paints fenced code with the shared smooth corner geometry', (
    tester,
  ) async {
    final theme = await _markdownTheme(tester);
    final painter = theme.builder!.call(
      const MD$Code(text: 'final answer = 42;', language: 'dart'),
      theme,
    );
    expect(painter, isA<AppMarkdownCodeBlockPainter>());
    final codePainter = painter! as AppMarkdownCodeBlockPainter;
    addTearDown(codePainter.dispose);
    expect(codePainter.shape, isA<SmoothRectangleBorder>());
    expect(codePainter.shape.smoothness, AppCorners.smoothness);
    expect(codePainter.shape.borderRadius, BorderRadius.circular(AppRadii.md));
    expect(codePainter.layout(320), isNot(Size.zero));
  });

  testWidgets('exposes only the code body to selection', (tester) async {
    final theme = await _markdownTheme(tester);
    final painter =
        theme.builder!.call(
              const MD$Code(text: 'final answer = 42;', language: 'dart'),
              theme,
            )!
            as AppMarkdownCodeBlockPainter;
    addTearDown(painter.dispose);
    painter.layout(320);

    final texts = painter.selectableTexts;
    expect(texts, hasLength(1));
    expect(texts.single.painter, same(painter.codePainter));
    expect(
      texts.single.offset.dy,
      greaterThan(painter.languagePainter!.height + theme.codePadding.top),
    );
  });

  testWidgets('uses a darker neutral background for inline code', (
    tester,
  ) async {
    final theme = await _markdownTheme(tester);
    final inlineCodeStyle = theme.textStyleFor(MD$Style.monospace);

    expect(inlineCodeStyle.backgroundColor, AppColors.inlineCodeBackground);
    expect(
      AppColors.inlineCodeBackground.computeLuminance(),
      lessThan(AppColors.propertyCardBackground.computeLuminance()),
    );
  });

  testWidgets('highlights common Skill markdown and Python fences', (
    tester,
  ) async {
    final theme = await _markdownTheme(tester);

    final markdownSpan = theme.codeHighlighter!.build(
      text: '# Heading\n\n**important**',
      language: 'markdown',
      textStyle: theme.resolvedCodeStyle,
      theme: theme,
    );
    final pythonSpan = theme.codeHighlighter!.build(
      text: 'def greet(name):\n    return "Hello"',
      language: 'py',
      textStyle: theme.resolvedCodeStyle,
      theme: theme,
    );

    expect(_leafColors(markdownSpan).length, greaterThan(1));
    expect(_leafColors(pythonSpan).length, greaterThan(1));
  });

  testWidgets('keeps unknown and unlabeled fences readable as plain code', (
    tester,
  ) async {
    final theme = await _markdownTheme(tester);

    for (final language in <String?>['made-up-language', null]) {
      final span = theme.codeHighlighter!.build(
        text: 'plain code',
        language: language,
        textStyle: theme.resolvedCodeStyle,
        theme: theme,
      );
      expect(span.text, 'plain code');
      expect(span.children, isNull);
    }
  });
}

Future<MarkdownThemeData> _markdownTheme(WidgetTester tester) async {
  late MarkdownThemeData theme;
  await tester.pumpWidget(
    CupertinoApp(
      home: Builder(
        builder: (context) {
          theme = AppMarkdownTheme.data(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return theme;
}

Set<Color?> _leafColors(InlineSpan span) {
  final colors = <Color?>{};

  void visit(InlineSpan current) {
    switch (current) {
      case TextSpan(children: final children?) when children.isNotEmpty:
        for (final child in children) {
          visit(child);
        }
      case TextSpan(text: final text?) when text.isNotEmpty:
        colors.add(current.style?.color);
      case TextSpan():
      case WidgetSpan():
    }
  }

  visit(span);
  return colors;
}
