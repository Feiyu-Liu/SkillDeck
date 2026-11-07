@Tags(['network'])
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_commands.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/https_proxy_resolver.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/libgit2_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/routing_git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_availability.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/source/git_application_source_adapter.dart';
import 'package:skills_workspace/src/native/source_transport/source_transport_native.dart';
import 'package:test/test.dart';

import '../support/git_transport/git_source_transport_contract.dart';

/// A small public repository of Agent Skills.
const _repository = 'https://github.com/anthropics/skills.git';

/// Real-network checks of public HTTPS Sources through the embedded libgit2
/// with system Git made unusable (ADR-0106). Run on demand:
/// `dart test -j 1 --run-skipped -t network test/network/`.
void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('skills-network-fetch-');
  });
  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  RoutingGitSourceTransport transport() => RoutingGitSourceTransport(
    libgit2: Libgit2SourceTransport(
      native: const SourceTransportNative(),
      proxySelector: HttpsProxyResolver().select,
    ),
    systemGit: SystemGitSourceTransport(
      commandBuilder: GitBareCommandBuilder(
        executable: path.join(scratch.path, 'missing-git'),
      ),
    ),
    systemGitAvailability: const _Unavailable(),
  );

  test('acquires public Skills from GitHub without system Git', () async {
    final adapter = GitApplicationSourceAdapter(transport: transport());
    final acquired = await adapter.acquireGit(
      GitSourceDescriptor(locator: _repository),
      selectedSkillNames: const <String>{},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );

    final source = acquired.valueOrNull;
    expect(source, isNotNull, reason: '${acquired.failureOrNull}');
    expect(source!.skills, isNotEmpty);
    expect(source.resolvedSourceRevision, matches(RegExp(r'^[0-9a-f]{40}$')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('fetches a branch and a commit object ID', () async {
    final subject = transport();
    final head = (await subject.fetchBare(
      GitSourceDescriptor(locator: _repository, ref: 'main'),
      repositoryPath: path.join(scratch.path, 'branch.git'),
      disabledHooksPath: scratch.path,
      cancellation: const NeverGitCancellation(),
    )).valueOrNull;
    expect(head, isNotNull);
    await subject.dispose(head!);

    final pinned = await subject.fetchBare(
      GitSourceDescriptor(locator: _repository, ref: head.resolvedRevision),
      repositoryPath: path.join(scratch.path, 'commit.git'),
      disabledHooksPath: scratch.path,
      cancellation: const NeverGitCancellation(),
    );
    expect(
      pinned.valueOrNull?.resolvedRevision,
      head.resolvedRevision,
      reason: '${pinned.failureOrNull?.code} ${pinned.failureOrNull?.context}',
    );
    await subject.dispose(pinned.valueOrNull!);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final class _Unavailable implements SystemGitAvailability {
  const _Unavailable();

  @override
  Future<bool> isAvailable() async => false;
}
