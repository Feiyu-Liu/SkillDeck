import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('observes only complete atomic generations', () async {
    const entryPath = String.fromEnvironment('ENTRY_PATH');
    const stopPath = String.fromEnvironment('STOP_PATH');
    const lengthText = String.fromEnvironment('CONTENT_LENGTH');
    if (entryPath.isEmpty || stopPath.isEmpty || lengthText.isEmpty) {
      throw StateError('Reader process configuration is required.');
    }
    final entry = File(entryPath);
    final stop = File(stopPath);
    final contentLength = int.parse(lengthText);
    print('cache-reader-ready');

    while (!await stop.exists()) {
      try {
        final decoded = jsonDecode(await entry.readAsString());
        if (decoded is! Map) {
          throw const FormatException('Entry is not an object.');
        }
        final content = decoded['translatedContent'];
        if (content is! String || content.length != contentLength) {
          throw const FormatException('Entry contains a partial generation.');
        }
        final expected = content.codeUnitAt(0);
        if (expected != 0x41 && expected != 0x42) {
          throw const FormatException('Entry contains an unknown generation.');
        }
        for (final codeUnit in content.codeUnits) {
          if (codeUnit != expected) {
            throw const FormatException('Entry mixes generations.');
          }
        }
      } on FileSystemException {
        if (!Platform.isWindows) rethrow;
      }
    }
  });
}
