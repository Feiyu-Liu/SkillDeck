import 'dart:isolate';
import 'dart:typed_data';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import '../native/revision_worker/revision_worker_protocol.dart';

RevisionWorkerCanonicalManifestPayload encodeCanonicalManifestInWorker(
  RevisionWorkerEncodeCanonicalManifestCommand command,
) {
  final manifestBytes = Uint8List.fromList(canonicalJson.encode(command.value));
  final fenceBytes = Uint8List.fromList(
    canonicalJson.encode(<String, Object?>{
      'schema': command.schemaVersion,
      'manifestSha256': sha256.convert(manifestBytes).toString(),
    }),
  );
  return RevisionWorkerCanonicalManifestPayload(
    manifestBytes: TransferableTypedData.fromList(<Uint8List>[manifestBytes]),
    completionFenceBytes: TransferableTypedData.fromList(<Uint8List>[
      fenceBytes,
    ]),
  );
}
