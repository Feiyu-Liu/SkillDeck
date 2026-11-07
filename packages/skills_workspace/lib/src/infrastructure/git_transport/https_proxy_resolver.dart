import 'dart:async';
import 'dart:io';

import '../../application/ports/source_transport_native_port.dart';
import 'git_proxy_choice.dart';

/// The host platforms whose proxy settings the resolver understands.
enum ProxyHostPlatform { macOS, windows, linux }

/// Chooses how a Git Source fetch reaches an HTTPS remote (ADR-0106).
///
/// Resolution order: an `https_proxy` or `HTTPS_PROXY` environment variable
/// (handled by the transport, including `no_proxy`), then `all_proxy` or
/// `ALL_PROXY`, then the operating system's HTTPS proxy on macOS and Windows,
/// then a direct connection. Only HTTP(S) proxies are used; SOCKS proxies and
/// automatic proxy configuration (PAC or WPAD) are not supported and fall
/// through to the next source.
final class HttpsProxyResolver {
  HttpsProxyResolver({
    Map<String, String>? environment,
    ProxyHostPlatform? platform,
    Future<String?> Function()? readMacOSSettings,
    Future<String?> Function()? readWindowsSettings,
  }) : _environment = environment ?? Platform.environment,
       _platform = platform ?? _currentPlatform(),
       _readMacOSSettings = readMacOSSettings ?? _runScutil,
       _readWindowsSettings = readWindowsSettings ?? _noWindowsSettings;

  final Map<String, String> _environment;
  final ProxyHostPlatform _platform;
  final Future<String?> Function() _readMacOSSettings;
  final Future<String?> Function() _readWindowsSettings;

  /// A [GitProxySelector] backed by this resolver.
  Future<GitProxyChoice> select(Uri remote) async {
    final host = remote.host.toLowerCase();
    if (_nonEmpty('https_proxy') != null || _nonEmpty('HTTPS_PROXY') != null) {
      return const GitProxyFromEnvironment();
    }
    final allProxy = _httpProxyUrl(
      _nonEmpty('all_proxy') ?? _nonEmpty('ALL_PROXY'),
    );
    if (allProxy != null) {
      final bypass = (_nonEmpty('no_proxy') ?? _nonEmpty('NO_PROXY') ?? '')
          .split(',');
      return matchesProxyBypass(host, bypass)
          ? const GitProxyDirect()
          : GitProxySpecified(allProxy);
    }
    final system = switch (_platform) {
      ProxyHostPlatform.macOS => parseMacOSProxySettings(
        await _safely(_readMacOSSettings),
      ),
      ProxyHostPlatform.windows => parseWindowsProxySettings(
        await _safely(_readWindowsSettings),
      ),
      ProxyHostPlatform.linux => null,
    };
    if (system == null || matchesProxyBypass(host, system.bypass)) {
      return const GitProxyDirect();
    }
    return GitProxySpecified(system.url);
  }

  String? _nonEmpty(String name) {
    final value = _environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// A system HTTPS proxy and the hosts that bypass it.
typedef SystemHttpsProxy = ({String url, List<String> bypass});

/// Parses `scutil --proxy` output into the HTTPS proxy, if one is enabled.
SystemHttpsProxy? parseMacOSProxySettings(String? output) {
  if (output == null) return null;
  final values = <String, String>{};
  final exceptions = <String>[];
  var inExceptions = false;
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (inExceptions) {
      if (line.startsWith('}')) {
        inExceptions = false;
        continue;
      }
      final separator = line.indexOf(':');
      if (separator > 0) exceptions.add(line.substring(separator + 1).trim());
      continue;
    }
    final separator = line.indexOf(' : ');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 3).trim();
    if (key == 'ExceptionsList') {
      inExceptions = value.startsWith('<array>');
      continue;
    }
    values[key] = value;
  }
  if (values['HTTPSEnable'] != '1') return null;
  final host = values['HTTPSProxy'];
  if (host == null || host.isEmpty) return null;
  final port = values['HTTPSPort'];
  final url = _httpProxyUrl(
    port == null || port.isEmpty || port == '0' ? host : '$host:$port',
  );
  if (url == null) return null;
  return (
    url: url,
    bypass: [
      ...exceptions,
      if (values['ExcludeSimpleHostnames'] == '1') '<local>',
    ],
  );
}

/// Parses `proxy TAB bypass TAB auto-config-flag` from the Windows query.
SystemHttpsProxy? parseWindowsProxySettings(String? output) {
  if (output == null) return null;
  final fields = output.split('\t');
  if (fields.length != 3) return null;
  final proxy = fields[0].trim();
  if (proxy.isEmpty) return null;
  String? selected;
  for (final entry in proxy.split(RegExp(r'[;\s]+'))) {
    if (entry.isEmpty) continue;
    final separator = entry.indexOf('=');
    if (separator < 0) {
      selected ??= entry;
    } else if (entry.substring(0, separator).toLowerCase() == 'https') {
      selected = entry.substring(separator + 1);
      break;
    }
  }
  final url = _httpProxyUrl(selected);
  if (url == null) return null;
  return (
    url: url,
    bypass: fields[1]
        .split(RegExp(r'[;\s]+'))
        .where((entry) => entry.isNotEmpty)
        .toList(),
  );
}

/// Whether [host] matches a proxy bypass entry.
///
/// Supports exact hosts, `*.example.com` and `.example.com` suffixes, a bare
/// `*`, and `<local>` for hosts without a dot. Network ranges are ignored.
bool matchesProxyBypass(String host, Iterable<String> entries) {
  final normalizedHost = host.toLowerCase();
  for (final rawEntry in entries) {
    var entry = rawEntry.trim().toLowerCase();
    if (entry.isEmpty) continue;
    if (entry == '*') return true;
    if (entry == '<local>') {
      if (!normalizedHost.contains('.')) return true;
      continue;
    }
    final schemeSeparator = entry.indexOf('://');
    if (schemeSeparator >= 0) entry = entry.substring(schemeSeparator + 3);
    final portSeparator = entry.lastIndexOf(':');
    if (portSeparator > 0 && !entry.contains(']')) {
      entry = entry.substring(0, portSeparator);
    }
    if (entry.startsWith('*.')) entry = entry.substring(1);
    if (entry.startsWith('.')) {
      if (normalizedHost.endsWith(entry) ||
          normalizedHost == entry.substring(1)) {
        return true;
      }
    } else if (normalizedHost == entry) {
      return true;
    }
  }
  return false;
}

/// Normalizes an HTTP(S) proxy address to a URL; rejects other schemes.
String? _httpProxyUrl(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final trimmed = value.trim();
  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return withScheme;
}

Future<String?> _safely(Future<String?> Function() read) async {
  try {
    return await read();
  } on Object {
    return null;
  }
}

ProxyHostPlatform _currentPlatform() {
  if (Platform.isMacOS) return ProxyHostPlatform.macOS;
  if (Platform.isWindows) return ProxyHostPlatform.windows;
  return ProxyHostPlatform.linux;
}

Future<String?> _runScutil() async {
  final result = await Process.run('/usr/sbin/scutil', const <String>[
    '--proxy',
  ]).timeout(const Duration(seconds: 5));
  return result.exitCode == 0 ? result.stdout as String : null;
}

Future<String?> _noWindowsSettings() async => null;

/// Reads the Windows proxy settings through [native], for composition.
Future<String?> Function() windowsProxySettingsFrom(
  SourceTransportNativePort native,
) => () async {
  final outcome = await native.windowsProxy();
  return outcome.status == SourceTransportStatus.ok ? outcome.value : null;
};
