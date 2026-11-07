import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_translation/src/atomic_file.dart';
import 'package:test/test.dart';

void main() {
  test('atomically creates and replaces a long-path file', () async {
    final temporary = await Directory.systemTemp.createTemp('atomic-file-');
    addTearDown(() => temporary.delete(recursive: true));
    final destination = p.joinAll([
      temporary.path,
      'a' * 64,
      'b' * 64,
      'c' * 64,
      'd' * 64,
      'translation.json',
    ]);
    if (Platform.isWindows) {
      expect(destination.length, greaterThan(260));
    }
    final writer = AtomicFileWriter();

    await writer.writeString(destination, 'first');
    expect(await File(destination).readAsString(), 'first');
    await writer.writeString(destination, 'replacement');
    expect(await File(destination).readAsString(), 'replacement');
  });
}
