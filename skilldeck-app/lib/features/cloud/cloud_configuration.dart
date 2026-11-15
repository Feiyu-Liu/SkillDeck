/// Build-time Cloud configuration; users never enter arbitrary service origins.
final class CloudConfiguration {
  const CloudConfiguration({required this.enabled, this.baseUri});
  factory CloudConfiguration.fromBuild() {
    const enabled = bool.fromEnvironment(
      'SKILLDECK_CLOUD_ENABLED',
      defaultValue: false,
    );
    if (!enabled) return const CloudConfiguration(enabled: false);
    final uri = Uri.tryParse(
      const String.fromEnvironment('SKILLDECK_CLOUD_BASE_URL'),
    );
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path)) {
      return const CloudConfiguration(enabled: true);
    }
    return CloudConfiguration(enabled: true, baseUri: Uri.parse(uri.origin));
  }
  final bool enabled;
  final Uri? baseUri;
  bool get configured =>
      enabled &&
      baseUri != null &&
      baseUri!.scheme == 'https' &&
      baseUri!.host.isNotEmpty &&
      baseUri!.userInfo.isEmpty &&
      !baseUri!.hasQuery &&
      !baseUri!.hasFragment &&
      ['', '/'].contains(baseUri!.path);
}
