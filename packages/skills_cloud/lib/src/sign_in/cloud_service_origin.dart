/// The origin of one SkillDeck Cloud environment: a scheme, host, and port.
///
/// The scheme is `https`. Plain `http` is accepted only for a loopback host,
/// for the local dev service.
final class CloudServiceOrigin {
  CloudServiceOrigin._(this._uri);

  /// Parses [value], or throws [ArgumentError] when it is not an origin.
  factory CloudServiceOrigin.parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(value, 'value', 'must be a service origin');
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if (scheme != 'https' &&
        !(scheme == 'http' && _loopbackHosts.contains(host))) {
      throw ArgumentError.value(
        value,
        'value',
        'must use https, or http on a loopback host',
      );
    }
    return CloudServiceOrigin._(
      Uri(scheme: scheme, host: host, port: uri.hasPort ? uri.port : null),
    );
  }

  static const _loopbackHosts = {'localhost', '127.0.0.1', '::1'};

  final Uri _uri;

  @override
  bool operator ==(Object other) =>
      other is CloudServiceOrigin && other._uri == _uri;

  @override
  int get hashCode => _uri.hashCode;

  @override
  String toString() => _uri.toString();
}

/// Package-internal helpers. Not exported.
extension CloudServiceOriginRequests on CloudServiceOrigin {
  /// The request URL for [path], which starts with `/`.
  Uri resolve(String path) => _uri.replace(path: path);

  /// Whether [uri] has exactly this origin's scheme, host, and port.
  bool owns(Uri uri) =>
      uri.userInfo.isEmpty &&
      uri.scheme.toLowerCase() == _uri.scheme &&
      uri.host.toLowerCase() == _uri.host &&
      uri.port == _uri.port;
}
