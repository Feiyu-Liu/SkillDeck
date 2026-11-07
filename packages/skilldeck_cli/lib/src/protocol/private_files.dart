import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _Chmod = int Function(Pointer<Utf8>, int);

void _chmod(String path, int mode) {
  if (Platform.isWindows) return;
  final chmod = DynamicLibrary.process().lookupFunction<_ChmodNative, _Chmod>(
    'chmod',
  );
  final nativePath = path.toNativeUtf8();
  try {
    if (chmod(nativePath, mode) != 0) {
      throw const FileSystemException('Cannot secure Command Host files.');
    }
  } finally {
    malloc.free(nativePath);
  }
}

Future<void> ensurePrivateDirectory(String path) async {
  await Directory(path).create(recursive: true);
  _chmod(path, 448); // 0700
}

Future<void> writePrivateFileAtomically(String path, List<int> bytes) async {
  // A private sibling staging directory protects the file even before chmod.
  final staging = await Directory(p.dirname(path)).createTemp('.command-host-');
  try {
    _chmod(staging.path, 448);
    final file = File(p.join(staging.path, 'discovery'));
    await file.create();
    _chmod(file.path, 384); // 0600, before writing the secret
    await file.writeAsBytes(bytes, flush: true);
    await file.rename(path);
  } finally {
    await staging.delete(recursive: true);
  }
}
