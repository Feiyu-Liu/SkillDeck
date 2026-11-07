import '../../application/ports/initial_import_ports.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../application/install/initial_import_models.dart';
import '../../domain/source_descriptor.dart';
import '../database/source_descriptor_codec.dart';

/// Keeps the versioned persistence codec behind the application port.
final class ApplicationSourcePayloadAdapter
    implements SourcePayloadEncodingPort {
  const ApplicationSourcePayloadAdapter({
    SourceDescriptorCodec codec = const SourceDescriptorCodec(),
  }) : _codec = codec;

  final SourceDescriptorCodec _codec;

  @override
  SourcePayloadEncodingResult encode(SourceDescriptor source) {
    try {
      final encoded = _codec.encode(source);
      return SourcePayloadEncoded(
        PersistedSourcePayload(
          kind: switch (encoded.kind) {
            'local' => WorkspaceSourceKind.local,
            'git' => WorkspaceSourceKind.git,
            'wellKnown' => WorkspaceSourceKind.wellKnown,
            'adoptedSnapshot' => WorkspaceSourceKind.adoptedSnapshot,
            _ => throw const SourceDescriptorCodecException('unsupportedKind'),
          },
          payloadSchemaVersion: encoded.payloadSchemaVersion,
          payloadJson: encoded.payloadJson,
        ),
      );
    } on SourceDescriptorCodecException catch (error) {
      return SourcePayloadEncodingFailure(
        error.reason == 'credentialBearingLocator'
            ? SourcePayloadEncodingFailureCode.credentialRejected
            : SourcePayloadEncodingFailureCode.invalidSource,
      );
    }
  }
}
