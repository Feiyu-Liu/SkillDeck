import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud_configuration.dart';
import '../sync/cloud_sync_session.dart';
import 'secure_cloud_session_store.dart';

import 'real_cloud_gateway.dart';
export 'real_cloud_gateway.dart';

/// Startup probes existing opt-in state before any secure-storage read or network.
Future<bool> hasPreviouslyEnabledCloudScope(
  CloudConfiguration configuration, {
  Future<Directory> Function()? supportDirectory,
}) async {
  final origin = configuration.baseUri;
  if (!configuration.configured || origin == null) return false;
  try {
    final support =
        await (supportDirectory ?? getApplicationSupportDirectory)();
    final namespace = sha256.convert(utf8.encode(origin.origin)).toString();
    return await BackgroundSqliteCloudDatabase.probeEnabledOptIn(
      path: p.join(
        support.path,
        'agent_skills',
        'cloud',
        namespace,
        'cloud.sqlite3',
      ),
      serviceOrigin: origin,
    );
  } catch (_) {
    return false;
  }
}

Future<AppCloudGateway> createCloudGateway(
  CloudConfiguration configuration, {
  Future<Directory> Function()? supportDirectory,
  CloudAuthClient Function(Uri origin)? authFactory,
  AppCloudSyncSession Function(CloudAuthClient, BackgroundSqliteCloudDatabase)?
  syncFactory,
}) async {
  final origin = configuration.baseUri;
  if (!configuration.configured || origin == null) {
    throw const CloudException(CloudErrorCode.invalidConfiguration);
  }
  final auth =
      authFactory?.call(origin) ??
      CloudAuthClient(
        transport: HttpsCloudTransport(baseUri: origin),
        secureStore: SecureCloudSessionStore(serviceOrigin: origin),
        launchBrowser: (uri) async {
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw const CloudException(CloudErrorCode.browserLaunch);
          }
        },
      );
  CloudDeviceScopeStore? database;
  try {
    final support =
        await (supportDirectory ?? getApplicationSupportDirectory)();
    final namespace = sha256.convert(utf8.encode(origin.origin)).toString();
    final directory = Directory(
      p.join(support.path, 'agent_skills', 'cloud', namespace),
    );
    await directory.create(recursive: true);
    database = await BackgroundSqliteCloudDatabase.open(
      path: p.join(directory.path, 'cloud.sqlite3'),
      serviceOrigin: origin,
    );
  } catch (_) {
    // A damaged Cloud database fences Sync, never account/device management.
    // Preserve the file for recovery; never delete or silently replace it.
  }
  return RealAppCloudGateway(
    auth: auth,
    database: database,
    syncFactory: syncFactory,
    deviceName: Platform.localHostname,
    platform: Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
        ? 'windows'
        : 'linux',
  );
}
