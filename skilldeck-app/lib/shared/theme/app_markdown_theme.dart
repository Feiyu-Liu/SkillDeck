import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_md/flutter_md.dart';

import 'app_palette.dart';
import 'app_markdown_code_block_painter.dart';
import 'app_markdown_code_highlighter.dart';
import 'app_metrics.dart';
import 'app_typography.dart';

abstract final class AppMarkdownTheme {
  static Map<String, TextStyle> _codeTheme(
    AppPalette colors,
  ) => <String, TextStyle>{
    'root': TextStyle(color: colors.bodyContent),
    'comment': TextStyle(
      color: colors.codeComment,
      fontStyle: FontStyle.italic,
    ),
    'quote': TextStyle(color: colors.codeComment, fontStyle: FontStyle.italic),
    'keyword': TextStyle(
      color: colors.codeKeyword,
      fontWeight: FontWeight.w600,
    ),
    'selector-tag': TextStyle(
      color: colors.codeKeyword,
      fontWeight: FontWeight.w600,
    ),
    'number': TextStyle(color: colors.codeNumber),
    'literal': TextStyle(color: colors.codeNumber),
    'variable': TextStyle(color: colors.codeNumber),
    'template-variable': TextStyle(color: colors.codeNumber),
    'string': TextStyle(color: colors.codeString),
    'doctag': TextStyle(color: colors.codeString),
    'regexp': TextStyle(color: colors.codeString),
    'link': TextStyle(color: colors.codeString),
    'title': TextStyle(color: colors.codeTitle, fontWeight: FontWeight.w600),
    'section': TextStyle(color: colors.codeTitle, fontWeight: FontWeight.w600),
    'type': TextStyle(color: colors.codeMeta),
    'built_in': TextStyle(color: colors.codeNumber),
    'meta': TextStyle(color: colors.codeMeta),
    'meta-keyword': TextStyle(color: colors.codeKeyword),
    'bullet': TextStyle(color: colors.codeTitle),
    'strong': const TextStyle(fontWeight: FontWeight.w700),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
  };

  static MarkdownThemeData data(BuildContext context) {
    final colors = AppPalette.of(context);
    final bodyStyle = AppTypography.body.copyWith(
      height: 1.6,
      color: colors.bodyContent,
    );
    return MarkdownThemeData(
      textStyle: bodyStyle,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      h1Style: AppTypography.title.copyWith(color: colors.textPrimary),
      h2Style: AppTypography.subtitle.copyWith(color: colors.textPrimary),
      h3Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
      h4Style: bodyStyle.copyWith(fontWeight: FontWeight.w600),
      h5Style: AppTypography.control.copyWith(color: colors.textPrimary),
      h6Style: AppTypography.caption.copyWith(color: colors.textPrimary),
      quoteStyle: AppTypography.bodyMuted.copyWith(
        height: 1.6,
        color: colors.textMuted,
      ),
      linkColor: colors.info,
      surfaceColor: colors.propertyCardBackground,
      monospaceBackgroundColor: colors.inlineCodeBackground,
      dividerColor: colors.divider,
      codeStyle: AppTypography.mono.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: colors.bodyContent,
      ),
      codeLanguageStyle: AppTypography.mono.copyWith(
        color: colors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      codeBackgroundColor: colors.surfaceMuted,
      codePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      codeBorder: BorderSide(color: colors.border),
      codeBorderRadius: BorderRadius.circular(AppRadii.md),
      codeTopSpacing: 12,
      codeTheme: _codeTheme(colors),
      codeHighlighter: const AppMarkdownCodeHighlighter(),
      builder: (block, theme) => switch (block) {
        MD$Code(:final text, :final language) => AppMarkdownCodeBlockPainter(
          text: text,
          language: language,
          theme: theme,
        ),
        _ => null,
      },
    );
  }
}
