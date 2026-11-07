const int _maximumDiagnosticLength = 4096;

String redactGitDiagnostic(String diagnostic, {String? locator}) {
  var redacted = diagnostic;
  if (locator != null && locator.isNotEmpty) {
    redacted = redacted.replaceAll(locator, redactGitLocator(locator));
  }

  redacted = redacted.replaceAllMapped(
    RegExp(
      r'([a-z][a-z0-9+.-]*://)([^\s/@]+(?::[^\s/@]*)?)@',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<redacted>@',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(r'([?&][^=\s&]+)=([^\s&#]*)'),
    (match) => '${match.group(1)}=<redacted>',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'\b(token|access[_-]?token|password|passwd|secret|authorization)=([^\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(r'\b[^\s/:@]+:[^\s@]+@(?=[^\s/:]+:)'),
    (_) => '<redacted>@',
  );

  if (redacted.length > _maximumDiagnosticLength) {
    return '${redacted.substring(0, _maximumDiagnosticLength)}\n[truncated]';
  }
  return redacted;
}

String redactGitLocator(String locator) {
  final sanitizedScpLocator = locator.replaceFirst(
    RegExp(r'^[^\s/:@]+:[^\s@]+@(?=[^\s/:]+:)'),
    '<redacted>@',
  );
  final uri = Uri.tryParse(sanitizedScpLocator);
  if (uri == null || !uri.hasScheme) {
    return sanitizedScpLocator;
  }

  final sanitizedQuery = <String, String>{};
  for (final key in uri.queryParameters.keys) {
    sanitizedQuery[key] = '<redacted>';
  }
  return uri
      .replace(
        userInfo: uri.userInfo.isEmpty ? null : '<redacted>',
        queryParameters: sanitizedQuery.isEmpty ? null : sanitizedQuery,
      )
      .toString();
}
