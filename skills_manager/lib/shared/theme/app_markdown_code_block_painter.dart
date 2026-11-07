import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:smooth_corner/smooth_corner.dart';

import 'app_corners.dart';

/// Paints fenced Markdown code with the app's continuous-corner geometry.
final class AppMarkdownCodeBlockPainter implements SelectableBlockPainter {
  AppMarkdownCodeBlockPainter({
    required String text,
    required String? language,
    required this.theme,
  }) : _padding = theme.codePadding,
       _topSpacing = theme.codeTopSpacing,
       _shape = SmoothRectangleBorder(
         borderRadius: theme.resolvedCodeBorderRadius,
         smoothness: AppCorners.smoothness,
         side: theme.resolvedCodeBorder,
       ),
       _backgroundPaint = Paint()
         ..color = theme.resolvedCodeBackgroundColor
         ..isAntiAlias = true
         ..style = PaintingStyle.fill,
       codePainter = TextPainter(
         text: _buildCodeText(text: text, language: language, theme: theme),
         textAlign: TextAlign.start,
         textDirection: theme.textDirection,
         textScaler: theme.textScaler,
       ),
       languagePainter = _buildLanguagePainter(
         language: language,
         theme: theme,
       );

  static const _languageGap = 6.0;

  final MarkdownThemeData theme;
  final EdgeInsets _padding;
  final double _topSpacing;
  final SmoothRectangleBorder _shape;
  final Paint _backgroundPaint;
  final TextPainter codePainter;
  final TextPainter? languagePainter;

  SmoothRectangleBorder get shape => _shape;

  @override
  Size get size => _size;
  Size _size = Size.zero;

  static TextSpan _buildCodeText({
    required String text,
    required String? language,
    required MarkdownThemeData theme,
  }) {
    final baseStyle = theme.resolvedCodeStyle;
    final highlighter = theme.codeHighlighter;
    if (highlighter == null) {
      return TextSpan(
        text: text,
        style: baseStyle.merge(theme.resolvedCodeTheme['root']),
      );
    }
    return highlighter.build(
      text: text,
      language: language,
      textStyle: baseStyle,
      theme: theme,
    );
  }

  static TextPainter? _buildLanguagePainter({
    required String? language,
    required MarkdownThemeData theme,
  }) {
    final label = language?.trim();
    if (label == null || label.isEmpty) return null;
    return TextPainter(
      text: TextSpan(text: label, style: theme.resolvedCodeLanguageStyle),
      textAlign: TextAlign.start,
      textDirection: theme.textDirection,
      textScaler: theme.textScaler,
    );
  }

  @override
  Size layout(double width) {
    if (width <= _padding.horizontal) {
      _size = Size.zero;
      return _size;
    }

    final contentWidth = width - _padding.horizontal;
    languagePainter?.layout(maxWidth: contentWidth);
    codePainter.layout(maxWidth: contentWidth);

    final labelHeight = languagePainter?.height ?? 0;
    final labelWidth = languagePainter?.width ?? 0;
    final gap = labelHeight > 0 && codePainter.height > 0 ? _languageGap : 0;
    return _size = Size(
      math.max(labelWidth, codePainter.width) + _padding.horizontal,
      labelHeight + gap + codePainter.height + _padding.vertical + _topSpacing,
    );
  }

  /// Only the code body is selectable, so copying skips the language label.
  @override
  List<SelectableBlockText> get selectableTexts {
    final labelHeight = languagePainter?.height ?? 0;
    final gap = labelHeight > 0 && codePainter.height > 0 ? _languageGap : 0;
    return [
      SelectableBlockText(
        painter: codePainter,
        offset: Offset(
          _padding.left,
          _topSpacing + _padding.top + labelHeight + gap,
        ),
      ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size, double offset) {
    if (size.width < _size.width) return;

    final blockRect = Rect.fromLTWH(
      0,
      offset + _topSpacing,
      size.width,
      _size.height - _topSpacing,
    );
    canvas.drawPath(
      _shape.getOuterPath(blockRect, textDirection: theme.textDirection),
      _backgroundPaint,
    );
    _shape.paint(canvas, blockRect, textDirection: theme.textDirection);

    var currentY = offset + _topSpacing + _padding.top;
    if (languagePainter != null) {
      languagePainter!.paint(canvas, Offset(_padding.left, currentY));
      currentY += languagePainter!.height;
      if (codePainter.height > 0) currentY += _languageGap;
    }
    codePainter.paint(canvas, Offset(_padding.left, currentY));
  }

  @override
  void handleTapDown(PointerDownEvent event) {}

  @override
  void handleTapUp(PointerUpEvent event) {}

  @override
  void dispose() {
    languagePainter?.dispose();
    codePainter.dispose();
  }
}
