import 'dart:convert';
import 'dart:io';

/// Separate process so the regression covers kernel locking, not just the
/// launcher's same-process queue. Its only output is a synchronization token.
Future<void> main(List<String> arguments) async {
  final file = await File(arguments.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.blockingExclusive);
    stdout.writeln('locked');
    await stdin.transform(utf8.decoder).first;
    await file.unlock();
  } finally {
    await file.close();
  }
}
