import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'failure.dart';

const appLocationFileName = 'app-location.json';

/// The App's durable relaunch hint, independent of its per-launch endpoint.
final class AppLocation {
  const AppLocation({
    required this.executablePath,
    required this.appVersion,
    this.bundleIdentifier,
  });

  final String executablePath;
  final String appVersion;
  final String? bundleIdentifier;

  Map<String, Object?> toJson() => {
    'executablePath': executablePath,
    if (bundleIdentifier != null) 'bundleIdentifier': bundleIdentifier,
    'appVersion': appVersion,
  };
}

Future<AppLocation> readAppLocation(String runDirectory) async {
  try {
    final file = File(p.join(runDirectory, appLocationFileName));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException();
    }
    final stat = await file.stat();
    if (stat.size > 64 * 1024 || (!Platform.isWindows && stat.mode & 63 != 0)) {
      throw const FormatException();
    }
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final executable = json['executablePath'] as String;
    final bundle = json['bundleIdentifier'] as String?;
    if (executable.isEmpty || (bundle != null && bundle.trim().isEmpty)) {
      throw const FormatException();
    }
    return AppLocation(
      executablePath: executable,
      appVersion: json['appVersion'] as String,
      bundleIdentifier: bundle,
    );
  } on Object {
    // Neither malformed content nor filesystem exceptions may expose paths.
    throw const ClientFailure(ClientFailureCode.appNotInstalled);
  }
}
