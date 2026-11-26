import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../../support/fake_cloud_service.dart';

void main() {
  group('CloudServiceOrigin', () {
    test('accepts production, staging, and loopback dev origins', () {
      for (final (value, expected) in [
        ('https://cloud.skilldeck.cc', 'https://cloud.skilldeck.cc'),
        (
          'https://cloud-staging.skilldeck.cc/',
          'https://cloud-staging.skilldeck.cc',
        ),
        ('HTTPS://Cloud.SkillDeck.cc:443', 'https://cloud.skilldeck.cc'),
        ('http://localhost:8787', 'http://localhost:8787'),
        ('http://127.0.0.1:8787', 'http://127.0.0.1:8787'),
        ('http://[::1]:8787', 'http://[::1]:8787'),
      ]) {
        expect(CloudServiceOrigin.parse(value).toString(), expected);
      }
      expect(
        CloudServiceOrigin.parse('https://Cloud.skilldeck.cc'),
        CloudServiceOrigin.parse('https://cloud.skilldeck.cc:443/'),
      );
      expect(
        CloudServiceOrigin.parse('http://localhost:8787'),
        isNot(CloudServiceOrigin.parse('http://localhost:8788')),
      );
    });

    test('rejects anything but a bare https or loopback origin', () {
      for (final value in [
        '',
        'cloud.skilldeck.cc',
        'http://cloud.skilldeck.cc',
        'http://192.168.1.2:8787',
        'ftp://cloud.skilldeck.cc',
        'https://cloud.skilldeck.cc/api',
        'https://cloud.skilldeck.cc?env=staging',
        'https://cloud.skilldeck.cc#top',
        'https://person:secret@cloud.skilldeck.cc',
        'https://',
      ]) {
        expect(
          () => CloudServiceOrigin.parse(value),
          throwsArgumentError,
          reason: value,
        );
      }
    });
  });

  group('CloudDevice', () {
    test('trims the name and keeps 64 code points', () {
      expect(
        CloudDevice(
          name: '  Studio Mac \n',
          platform: CloudDevicePlatform.macos,
        ).name,
        'Studio Mac',
      );
      final long = CloudDevice(
        name: '${'😀' * 63}abc',
        platform: CloudDevicePlatform.macos,
      );
      expect(long.name.runes, hasLength(CloudDevice.maxNameLength));
      expect(long.name, '${'😀' * 63}a');
      expect(CloudDevicePlatform.macos.wireName, 'macos');
    });

    test('rejects an empty name', () {
      for (final name in ['', '   ']) {
        expect(
          () => CloudDevice(name: name, platform: CloudDevicePlatform.macos),
          throwsArgumentError,
        );
      }
    });
  });

  test('no public value prints a secret or the email', () async {
    final service = FakeCloudService();
    final store = InMemoryCloudSessionStore();
    final signIn = service.signIn(store);
    final pending = await signIn.start(device) as PendingSignIn;
    final account = CloudAccount(
      id: 'account-1',
      email: accountEmail,
      sessionExpiresAt: DateTime.utc(2026, 12, 26),
    );
    final values = <Object>[
      origin,
      device,
      signIn,
      store,
      pending,
      account,
      StoredCloudSession(origin: origin, token: sessionToken),
      const CloudSignInStartFailed(CloudFailureCode.protocol),
      CloudSignInSucceeded(account),
      const CloudSignInDenied(),
      const CloudSignInExpired(),
      const CloudSignInCancelled(),
      const CloudSignInFailed(CloudFailureCode.network),
      CloudSignedIn(account),
      const CloudSignInRequired(),
      const CloudSessionUnavailable(CloudFailureCode.server),
      ...CloudFailureCode.values,
    ];
    for (final value in values) {
      final text = value.toString();
      for (final secret in [
        sessionToken,
        deviceCodeValue,
        userCodeValue,
        accountEmail,
      ]) {
        expect(text, isNot(contains(secret)), reason: '${value.runtimeType}');
      }
    }
    pending.cancel();
  });
}
