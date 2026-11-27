import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Installation-local seed for deriving opaque source identities.
final class CloudDeviceIdentity {
  CloudDeviceIdentity._(List<int> seed) : _hmac = Hmac(sha256, seed);

  static final _loading = <String, Future<CloudDeviceIdentity>>{};
  final Hmac _hmac;

  static Future<CloudDeviceIdentity> load(String supportDirectory) {
    final path = p.join(supportDirectory, 'cloud', 'source-id-seed');
    return _loading.putIfAbsent(path, () async {
      try {
        return await _load(File(path));
      } finally {
        _loading.remove(path);
      }
    });
  }

  static Future<CloudDeviceIdentity> _load(File file) async {
    if (await file.exists()) {
      final seed = await file.readAsBytes();
      if (seed.length != 32) throw StateError('cloud_installation_id_invalid');
      return CloudDeviceIdentity._(seed);
    }

    final random = Random.secure();
    final seed = List.generate(32, (_) => random.nextInt(256));
    await file.parent.create(recursive: true);
    // The App holds the Workspace process lock, and the loader serializes
    // concurrent reads within that process.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(seed, flush: true);
    await temporary.rename(file.path);
    return CloudDeviceIdentity._(seed);
  }

  String sourceIdFor(List<String?> sourceIdentity) => _hmac
      .convert(utf8.encode(jsonEncode(['source-v1', ...sourceIdentity])))
      .toString();
}
