import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/data/secure_cloud_session_store.dart';
import 'package:skills_manager/features/cloud/data/macos_web_authenticator.dart';

final cloudIsMacOSProvider = Provider<bool>((ref) => Platform.isMacOS);

final cloudOriginDefineProvider = Provider<String>(
  (ref) => const String.fromEnvironment('SKILLDECK_CLOUD_ORIGIN'),
);

/// A valid origin on macOS is the single availability gate for Cloud.
final cloudOriginProvider = Provider<CloudServiceOrigin?>((ref) {
  if (!ref.watch(cloudIsMacOSProvider)) return null;
  try {
    return CloudServiceOrigin.parse(ref.watch(cloudOriginDefineProvider));
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
});

final cloudHttpClientProvider = Provider<http.Client?>((ref) {
  if (ref.watch(cloudOriginProvider) == null) return null;
  final client = _NonRedirectingCloudClient(
    CupertinoClient.fromSessionConfiguration(
      URLSessionConfiguration.ephemeralSessionConfiguration(),
    ),
  );
  ref.onDispose(client.close);
  return client;
});

final cloudSessionStoreProvider = Provider<CloudSessionStore>(
  (ref) => const SecureCloudSessionStore(),
);

final cloudSignInProvider = Provider<CloudSignIn?>((ref) {
  final origin = ref.watch(cloudOriginProvider);
  if (origin == null) return null;
  final client = ref.watch(cloudHttpClientProvider);
  if (client == null) return null;
  return CloudSignIn(
    origin: origin,
    client: client,
    store: ref.watch(cloudSessionStoreProvider),
  );
});

final cloudDeviceProvider = Provider<Future<CloudDevice> Function()>(
  (ref) => () async {
    final result = await Process.run('/usr/sbin/scutil', [
      '--get',
      'ComputerName',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Cannot read the macOS computer name.');
    }
    return CloudDevice(
      name: result.stdout as String,
      platform: CloudDevicePlatform.macos,
    );
  },
);

final cloudWebAuthenticatorProvider = Provider<CloudWebAuthenticator>(
  (ref) => const MacosWebAuthenticator(),
);

/// Cloud requests must never forward a bearer token or device code.
final class _NonRedirectingCloudClient extends http.BaseClient {
  _NonRedirectingCloudClient(this._client);

  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
