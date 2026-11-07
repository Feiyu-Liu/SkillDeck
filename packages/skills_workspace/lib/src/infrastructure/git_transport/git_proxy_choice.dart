/// How a Git Source fetch reaches an HTTPS remote.
sealed class GitProxyChoice {
  const GitProxyChoice();
}

/// Connect directly to the remote.
final class GitProxyDirect extends GitProxyChoice {
  const GitProxyDirect();
}

/// Let the transport honour `https_proxy`, `HTTPS_PROXY`, and `no_proxy`.
final class GitProxyFromEnvironment extends GitProxyChoice {
  const GitProxyFromEnvironment();
}

/// Use one explicit proxy, for example the operating system's proxy setting.
///
/// [url] may carry proxy credentials and must never reach diagnostics.
final class GitProxySpecified extends GitProxyChoice {
  const GitProxySpecified(this.url);

  final String url;
}

/// Chooses the proxy for one remote.
typedef GitProxySelector = Future<GitProxyChoice> Function(Uri remote);

/// The selector used when no proxy policy is supplied.
Future<GitProxyChoice> directGitProxy(Uri remote) async =>
    const GitProxyDirect();
