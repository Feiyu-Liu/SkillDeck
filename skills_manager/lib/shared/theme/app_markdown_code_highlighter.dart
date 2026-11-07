import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:highlight/highlight_core.dart' as highlight;
import 'package:highlight/languages/bash.dart' as bash_language;
import 'package:highlight/languages/dart.dart' as dart_language;
import 'package:highlight/languages/javascript.dart' as javascript_language;
import 'package:highlight/languages/json.dart' as json_language;
import 'package:highlight/languages/markdown.dart' as markdown_language;
import 'package:highlight/languages/plaintext.dart' as plaintext_language;
import 'package:highlight/languages/python.dart' as python_language;
import 'package:highlight/languages/typescript.dart' as typescript_language;
import 'package:highlight/languages/xml.dart' as xml_language;
import 'package:highlight/languages/yaml.dart' as yaml_language;

/// Syntax highlighting tuned for the languages commonly embedded in Skills.
final class AppMarkdownCodeHighlighter implements MarkdownCodeHighlighter {
  const AppMarkdownCodeHighlighter();

  static const _aliases = <String, String>{
    'js': 'javascript',
    'ts': 'typescript',
    'md': 'markdown',
    'mkd': 'markdown',
    'mkdown': 'markdown',
    'py': 'python',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'yml': 'yaml',
    'html': 'xml',
    'text': 'plaintext',
    'txt': 'plaintext',
  };
  static const _languages = <String>{
    'bash',
    'dart',
    'javascript',
    'json',
    'markdown',
    'plaintext',
    'python',
    'typescript',
    'xml',
    'yaml',
  };

  static final highlight.Highlight _highlighter = _createHighlighter();

  static highlight.Highlight _createHighlighter() {
    return highlight.Highlight()..registerLanguages(<String, highlight.Mode>{
      'bash': bash_language.bash,
      'dart': dart_language.dart,
      'javascript': javascript_language.javascript,
      'json': json_language.json,
      'markdown': markdown_language.markdown,
      'plaintext': plaintext_language.plaintext,
      'python': python_language.python,
      'typescript': typescript_language.typescript,
      'xml': xml_language.xml,
      'yaml': yaml_language.yaml,
    });
  }

  @override
  TextSpan build({
    required String text,
    required String? language,
    required TextStyle textStyle,
    required MarkdownThemeData theme,
  }) {
    final baseStyle = textStyle.merge(theme.resolvedCodeTheme['root']);
    final normalizedLanguage = _normalizeLanguage(language);
    if (normalizedLanguage == null) {
      return TextSpan(text: text, style: baseStyle);
    }

    final nodes = _highlighter.parse(text, language: normalizedLanguage).nodes;
    if (nodes == null || nodes.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    return TextSpan(
      style: baseStyle,
      children: nodes
          .map<InlineSpan>(
            (node) =>
                _nodeToSpan(node: node, theme: theme, parentStyle: baseStyle),
          )
          .toList(growable: false),
    );
  }

  static String? _normalizeLanguage(String? language) {
    final normalized = language?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    final resolved = _aliases[normalized] ?? normalized;
    return _languages.contains(resolved) ? resolved : null;
  }

  static InlineSpan _nodeToSpan({
    required highlight.Node node,
    required MarkdownThemeData theme,
    required TextStyle parentStyle,
  }) {
    final style = theme.codeTextStyleFor(
      node.className,
      baseStyle: parentStyle,
    );
    final children = node.children;
    if (children != null && children.isNotEmpty) {
      return TextSpan(
        style: style,
        children: children
            .map<InlineSpan>(
              (child) =>
                  _nodeToSpan(node: child, theme: theme, parentStyle: style),
            )
            .toList(growable: false),
      );
    }
    return TextSpan(text: node.value ?? '', style: style);
  }
}
