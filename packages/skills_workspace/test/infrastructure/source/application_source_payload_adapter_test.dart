import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/source/application_source_payload_adapter.dart';
import 'package:test/test.dart';

void main() {
  const adapter = ApplicationSourcePayloadAdapter();

  test(
    'encodes credential-free source payload behind the application port',
    () {
      final result =
          adapter.encode(
                LocalSourceDescriptor(locator: '/source', skillPath: 'review'),
              )
              as SourcePayloadEncoded;

      expect(result.payload.kind, WorkspaceSourceKind.local);
      expect(result.payload.payloadSchemaVersion, 1);
      expect(result.payload.payloadJson, contains('review'));
    },
  );

  test('rejects credential-bearing Git provenance', () {
    final result = adapter.encode(
      GitSourceDescriptor(
        locator: 'https://user:secret@example.test/source.git',
      ),
    );

    expect(
      (result as SourcePayloadEncodingFailure).code,
      SourcePayloadEncodingFailureCode.credentialRejected,
    );
  });
}
