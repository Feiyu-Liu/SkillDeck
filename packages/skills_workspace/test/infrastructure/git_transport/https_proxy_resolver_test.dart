import 'dart:io';

import 'package:skills_workspace/src/infrastructure/git_transport/git_proxy_choice.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/https_proxy_resolver.dart';
import 'package:test/test.dart';

final _github = Uri.parse('https://github.com/owner/repo.git');

const _clashScutil = '''
<dictionary> {
  ExceptionsList : <array> {
    0 : 127.0.0.1
    1 : *.local
    2 : 169.254/16
  }
  ExcludeSimpleHostnames : 1
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
  ProxyAutoConfigEnable : 0
  SOCKSEnable : 1
  SOCKSPort : 7891
  SOCKSProxy : 127.0.0.1
}
''';

void main() {
  HttpsProxyResolver resolver({
    Map<String, String> environment = const {},
    ProxyHostPlatform platform = ProxyHostPlatform.linux,
    String? macOS,
    String? windows,
  }) => HttpsProxyResolver(
    environment: environment,
    platform: platform,
    readMacOSSettings: () async => macOS,
    readWindowsSettings: () async => windows,
  );

  group('resolution order', () {
    test('lets the transport honour HTTPS environment proxies first', () async {
      for (final name in const ['https_proxy', 'HTTPS_PROXY']) {
        final choice = await resolver(
          environment: {name: 'http://env.example:3128'},
          platform: ProxyHostPlatform.macOS,
          macOS: _clashScutil,
        ).select(_github);
        expect(choice, isA<GitProxyFromEnvironment>(), reason: name);
      }
    });

    test('uses an HTTP all_proxy unless no_proxy bypasses the host', () async {
      final specified = await resolver(
        environment: {'ALL_PROXY': 'proxy.example:8080'},
      ).select(_github);
      expect((specified as GitProxySpecified).url, 'http://proxy.example:8080');

      final bypassed = await resolver(
        environment: {
          'all_proxy': 'http://proxy.example:8080',
          'no_proxy': 'localhost,.github.com',
        },
      ).select(_github);
      expect(bypassed, isA<GitProxyDirect>());

      final socks = await resolver(
        environment: {'ALL_PROXY': 'socks5://127.0.0.1:7891'},
      ).select(_github);
      expect(socks, isA<GitProxyDirect>());
    });

    test('falls back to the macOS system HTTPS proxy', () async {
      final choice = await resolver(
        platform: ProxyHostPlatform.macOS,
        macOS: _clashScutil,
      ).select(_github);
      expect((choice as GitProxySpecified).url, 'http://127.0.0.1:7890');
    });

    test('falls back to the Windows system HTTPS proxy', () async {
      final choice = await resolver(
        platform: ProxyHostPlatform.windows,
        windows: 'http=127.0.0.1:7890;https=127.0.0.1:7891\t<local>\t0',
      ).select(_github);
      expect((choice as GitProxySpecified).url, 'http://127.0.0.1:7891');
    });

    test('connects directly when nothing is configured or readable', () async {
      expect(await resolver().select(_github), isA<GitProxyDirect>());
      expect(
        await resolver(platform: ProxyHostPlatform.macOS).select(_github),
        isA<GitProxyDirect>(),
      );
      expect(
        await HttpsProxyResolver(
          environment: const {},
          platform: ProxyHostPlatform.windows,
          readWindowsSettings: () async => throw const OSError('denied'),
        ).select(_github),
        isA<GitProxyDirect>(),
      );
    });

    test('bypasses the system proxy for excepted hosts', () async {
      final choice = await resolver(
        platform: ProxyHostPlatform.macOS,
        macOS: _clashScutil,
      ).select(Uri.parse('https://intranet.local/repo.git'));
      expect(choice, isA<GitProxyDirect>());
    });
  });

  group('macOS settings', () {
    test('ignores a disabled HTTPS proxy and automatic configuration', () {
      expect(
        parseMacOSProxySettings(
          _clashScutil.replaceFirst('HTTPSEnable : 1', 'HTTPSEnable : 0'),
        ),
        isNull,
      );
      expect(
        parseMacOSProxySettings('''
<dictionary> {
  ProxyAutoConfigEnable : 1
  ProxyAutoConfigURLString : http://wpad/proxy.pac
}
'''),
        isNull,
      );
      expect(parseMacOSProxySettings(null), isNull);
    });

    test('collects exceptions and simple-hostname exclusion', () {
      final proxy = parseMacOSProxySettings(_clashScutil)!;
      expect(proxy.bypass, ['127.0.0.1', '*.local', '169.254/16', '<local>']);
    });

    test('keeps a proxy without a port', () {
      final proxy = parseMacOSProxySettings('''
<dictionary> {
  HTTPSEnable : 1
  HTTPSProxy : proxy.corp
}
''')!;
      expect(proxy.url, 'http://proxy.corp');
    });
  });

  group('Windows settings', () {
    test('accepts a single proxy for every scheme', () {
      final proxy = parseWindowsProxySettings(
        'proxy.corp:8080\t*.corp.example;<local>\t0',
      )!;
      expect(proxy.url, 'http://proxy.corp:8080');
      expect(proxy.bypass, ['*.corp.example', '<local>']);
    });

    test('ignores automatic configuration without a static proxy', () {
      expect(parseWindowsProxySettings('\t\t1'), isNull);
      expect(parseWindowsProxySettings('malformed'), isNull);
      expect(parseWindowsProxySettings(null), isNull);
      expect(parseWindowsProxySettings('socks=127.0.0.1:1080\t\t0'), isNull);
    });
  });

  group('bypass matching', () {
    test('matches exact, suffix, wildcard, and simple hosts', () {
      expect(matchesProxyBypass('github.com', ['github.com']), isTrue);
      expect(matchesProxyBypass('api.github.com', ['*.github.com']), isTrue);
      expect(matchesProxyBypass('github.com', ['.github.com']), isTrue);
      expect(
        matchesProxyBypass('github.com', ['https://github.com:443']),
        isTrue,
      );
      expect(matchesProxyBypass('intranet', ['<local>']), isTrue);
      expect(matchesProxyBypass('github.com', ['*']), isTrue);
      expect(
        matchesProxyBypass('github.com', ['<local>', 'gitlab.com']),
        isFalse,
      );
      expect(matchesProxyBypass('notgithub.com', ['.github.com']), isFalse);
    });
  });
}
