import 'dart:io';

import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';

void main() {
  final engine = RevisionNativeEngine.open();
  try {
    stdout.writeln(engine.version());
  } finally {
    engine.close();
  }
}
