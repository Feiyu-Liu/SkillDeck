import 'package:skills_workspace/src/infrastructure/git_transport/libgit2_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:skills_workspace/src/native/source_transport/source_transport_native.dart';
import 'package:test/test.dart';

import '../../support/git_transport/git_http_backend_server.dart';
import '../../support/git_transport/git_source_transport_contract.dart';

void main() {
  group('SystemGitSourceTransport', () {
    defineGitSourceTransportContract(
      createTransport:
          ({required int maximumFileCount, required int maximumByteSize}) =>
              SystemGitSourceTransport(
                maximumFileCount: maximumFileCount,
                maximumRepositoryEntryCount: maximumFileCount,
                maximumByteSize: maximumByteSize,
              ),
      serve: (fixture) async => fixture.workingPath,
    );
  });

  group('Libgit2SourceTransport over smart HTTP', () {
    defineGitSourceTransportContract(
      createTransport:
          ({required int maximumFileCount, required int maximumByteSize}) =>
              Libgit2SourceTransport(
                native: const SourceTransportNative(),
                maximumFileCount: maximumFileCount,
                maximumRepositoryEntryCount: maximumFileCount,
                maximumByteSize: maximumByteSize,
                allowLoopbackHttpForTesting: true,
              ),
      serve: (fixture) async {
        final server = await GitHttpBackendServer.start(
          projectRoot: fixture.root.path,
        );
        addTearDown(server.close);
        return server.locatorFor('source');
      },
    );
  });
}
