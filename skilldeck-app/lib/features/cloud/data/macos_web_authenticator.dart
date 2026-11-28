import 'package:flutter/services.dart';
import 'package:skills_cloud/skills_cloud.dart';

/// The App-owned macOS system sign-in window.
final class MacosWebAuthenticator implements CloudWebAuthenticator {
  const MacosWebAuthenticator();

  static const _channel = MethodChannel('skilldeck/web_auth');

  @override
  Future<Uri?> authenticate(Uri url, {required String callbackScheme}) async {
    final callback = await _channel.invokeMethod<String>('authenticate', {
      'url': url.toString(),
      'callbackScheme': callbackScheme,
    });
    return callback == null ? null : Uri.parse(callback);
  }
}
