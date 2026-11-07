import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:test/test.dart';

import 'git_source_fixture.dart';

/// Creates the transport under test with the given Source limits.
typedef GitSourceTransportFactory =
    GitSourceTransport Function({
      required int maximumFileCount,
      required int maximumByteSize,
    });

/// Serves [fixture] to the transport and returns its locator.
typedef GitSourceLocatorFactory =
    Future<String> Function(GitSourceFixture fixture);

/// The behavior every [GitSourceTransport] must share, so Sources acquired
/// through any transport produce identical trees and failures.
void defineGitSourceTransportContract({
  required GitSourceTransportFactory createTransport,
  required GitSourceLocatorFactory serve,
}) {
  late GitSourceFixture fixture;
  late Directory scratch;
  late String hooks;

  setUp(() async {
    fixture = await GitSourceFixture.create();
    scratch = await Directory.systemTemp.createTemp(
      'skills-workspace-transport-contract-',
    );
    hooks = path.join(scratch.path, 'disabled-hooks');
    await Directory(hooks).create();
  });

  tearDown(() async {
    await fixture.dispose();
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  GitSourceTransport transport({
    int maximumFileCount = 1000,
    int maximumByteSize = 50 * 1024 * 1024,
  }) => createTransport(
    maximumFileCount: maximumFileCount,
    maximumByteSize: maximumByteSize,
  );

  Future<GitTransportResult<GitBareSource>> fetch(
    GitSourceTransport subject, {
    String? ref,
    GitCancellationSignal cancellation = const NeverGitCancellation(),
  }) async => subject.fetchBare(
    GitSourceDescriptor(locator: await serve(fixture), ref: ref),
    repositoryPath: path.join(scratch.path, 'source.git'),
    disabledHooksPath: hooks,
    cancellation: cancellation,
  );

  test('fetches HEAD and lists the selection without a checkout', () async {
    final subject = transport();
    final fetched = (await fetch(subject)).valueOrNull!;

    expect(fetched.resolvedRevision, await fixture.revParse('main'));
    expect(
      File(
        path.join(fetched.repositoryPath, 'skills', 'demo', 'SKILL.md'),
      ).existsSync(),
      isFalse,
    );
    final entries = (await subject.listTree(
      fetched,
      repositorySubpath: 'skills/demo',
      cancellation: const NeverGitCancellation(),
    )).valueOrNull!;
    expect(
      [
        for (final entry in entries)
          (entry.relativePath, entry.kind, entry.executable),
      ],
      [
        ('skills/demo/SKILL.md', GitTreeEntryKind.blob, false),
        ('skills/demo/docs-link', GitTreeEntryKind.symbolicLink, false),
        ('skills/demo/docs/binary.bin', GitTreeEntryKind.blob, false),
        ('skills/demo/run.sh', GitTreeEntryKind.blob, true),
      ],
    );

    final contents = await readAll(subject, fetched, entries);
    expect(
      utf8.decode(contents['skills/demo/SKILL.md']!),
      GitSourceFixture.skillBody,
    );
    expect(
      contents['skills/demo/docs/binary.bin'],
      GitSourceFixture.binaryBytes,
    );
    expect(utf8.decode(contents['skills/demo/docs-link']!), 'docs');

    final linkEntry = await subject.listTree(
      fetched,
      repositorySubpath: 'skills/demo/docs-link',
      cancellation: const NeverGitCancellation(),
    );
    expect(linkEntry.failureOrNull, isNull);
    expect(linkEntry.valueOrNull!.single.relativePath, 'skills/demo/docs-link');
    expect(linkEntry.valueOrNull!.single.kind, GitTreeEntryKind.symbolicLink);

    await subject.dispose(fetched);
    expect(Directory(fetched.repositoryPath).existsSync(), isFalse);
  });

  test('fetches a named branch', () async {
    final subject = transport();
    final fetched = (await fetch(subject, ref: 'feature')).valueOrNull!;
    expect(fetched.resolvedRevision, await fixture.revParse('feature'));

    final entries = (await subject.listTree(
      fetched,
      repositorySubpath: 'skills/demo',
      cancellation: const NeverGitCancellation(),
    )).valueOrNull!;
    final contents = await readAll(subject, fetched, entries);
    expect(
      utf8.decode(contents['skills/demo/SKILL.md']!),
      GitSourceFixture.featureBody,
    );
    await subject.dispose(fetched);
  });

  test('fails a missing ref and leaves no repository behind', () async {
    final subject = transport();
    final result = await fetch(subject, ref: 'no-such-branch');

    expect(result.failureOrNull, isNotNull);
    expect(
      Directory(path.join(scratch.path, 'source.git')).existsSync(),
      isFalse,
    );
  });

  test('retains gitlinks for selected-root validation', () async {
    await fixture.addGitlink();
    final subject = transport();
    final fetched = (await fetch(subject)).valueOrNull!;
    final listed = await subject.listTree(
      fetched,
      repositorySubpath: 'skills/demo',
      cancellation: const NeverGitCancellation(),
    );

    expect(listed.failureOrNull, isNull);
    expect(
      listed.valueOrNull!.any(
        (entry) => entry.kind == GitTreeEntryKind.gitlink,
      ),
      isTrue,
    );
    await subject.dispose(fetched);
  });

  test('bounds the listed file count and the streamed bytes', () async {
    final counted = transport(maximumFileCount: 2);
    final fetched = (await fetch(counted)).valueOrNull!;
    final listed = await counted.listTree(
      fetched,
      repositorySubpath: 'skills/demo',
      cancellation: const NeverGitCancellation(),
    );
    expect(
      listed.failureOrNull?.context['reason'],
      'repositoryEntryLimitExceeded',
    );

    final sized = transport(maximumByteSize: 4);
    final entries = (await sized.listTree(
      fetched,
      repositorySubpath: 'skills/demo',
      cancellation: const NeverGitCancellation(),
    )).valueOrNull!;
    final streamed = await sized.streamBlobs(
      fetched,
      requests: [
        for (final entry in entries)
          GitBlobRequest(
            objectId: entry.objectId,
            relativePath: entry.relativePath,
          ),
      ],
      onChunk: (_) async {},
      cancellation: const NeverGitCancellation(),
    );
    expect(streamed.failureOrNull?.code, GitTransportFailureCode.invalidOutput);
    expect(streamed.failureOrNull?.context['reason'], 'blobBytesExceededLimit');
    await sized.dispose(fetched);
  });

  test('honours cancellation that precedes the fetch', () async {
    final subject = transport();
    final result = await fetch(
      subject,
      cancellation: const AlreadyCancelledGitSignal(),
    );

    expect(result.failureOrNull?.code, GitTransportFailureCode.cancelled);
  });
}

/// Reads every listed entry through [subject] and joins the chunks.
Future<Map<String, Uint8List>> readAll(
  GitSourceTransport subject,
  GitBareSource source,
  List<GitTreeEntry> entries,
) async {
  final builders = <String, BytesBuilder>{};
  final result = await subject.streamBlobs(
    source,
    requests: [
      for (final entry in entries)
        GitBlobRequest(
          objectId: entry.objectId,
          relativePath: entry.relativePath,
        ),
    ],
    onChunk: (chunk) async {
      builders
          .putIfAbsent(chunk.request.relativePath, BytesBuilder.new)
          .add(chunk.bytes);
    },
    cancellation: const NeverGitCancellation(),
  );
  expect(result.failureOrNull, isNull);
  return {
    for (final MapEntry(:key, :value) in builders.entries)
      key: value.takeBytes(),
  };
}

final class NeverGitCancellation implements GitCancellationSignal {
  const NeverGitCancellation();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;
}

final class AlreadyCancelledGitSignal implements GitCancellationSignal {
  const AlreadyCancelledGitSignal();

  @override
  bool get isCancelled => true;

  @override
  Future<void> get whenCancelled => Future<void>.value();
}
