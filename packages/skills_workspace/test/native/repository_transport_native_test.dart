import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/repository_transport_native_port.dart';
import 'package:skills_workspace/src/native/repository_transport/repository_transport_native.dart';
import 'package:test/test.dart';

import '../support/git_transport/git_http_backend_server.dart';

void main() {
  const native = RepositoryTransportNative(allowLoopbackHttpForTesting: true);
  late Directory scratch;
  late String source;
  late String remote;
  late String incoming;
  late String commit;
  late String parentCommit;
  late String token;
  late ffi.Pointer<ffi.Int32> cancellation;
  final servers = <GitHttpBackendServer>[];

  Future<String> git(List<String> arguments, {String? cwd}) async {
    final result = await Process.run('git', arguments, workingDirectory: cwd);
    if (result.exitCode != 0) fail('Git fixture command failed.');
    return (result.stdout as String).trim();
  }

  Future<GitHttpBackendServer> server({
    bool authenticated = true,
    String? redirectTo,
    void Function(HttpRequest)? onRequest,
    void Function(int)? onRequestBody,
  }) async {
    final value = await GitHttpBackendServer.start(
      projectRoot: scratch.path,
      bearerToken: authenticated ? token : null,
      redirectTo: redirectTo,
      onRequest: onRequest,
      onRequestBody: onRequestBody,
    );
    servers.add(value);
    return value;
  }

  Future<RepositoryTransportOutcome> push(
    GitHttpBackendServer backend, {
    List<String>? refspecs,
    List<String>? headers,
    RepositoryTransportNative transport = native,
    String? url,
  }) => transport.push(
    repositoryPath: source,
    url: url ?? backend.locatorFor('remote.git'),
    refspecs: refspecs ?? ['$commit:refs/heads/main'],
    customHeaders: headers ?? ['Authorization: Bearer $token'],
    cancelFlagAddress: cancellation.address,
  );

  Future<void> noPersistedAuth() async {
    for (final root in [source, incoming]) {
      final config = await File(path.join(root, 'config')).readAsString();
      expect(config, isNot(contains(token)));
      expect(config, isNot(contains('Authorization')));
      expect(config, isNot(contains('[remote ')));
      expect(await File(path.join(root, 'FETCH_HEAD')).exists(), isFalse);
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          expect(latin1.decode(bytes), isNot(contains(token)));
          expect(latin1.decode(bytes), isNot(contains('http://127.0.0.1:')));
        }
      }
    }
  }

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('repository-native-');
    source = path.join(scratch.path, 'source.git');
    remote = path.join(scratch.path, 'remote.git');
    incoming = path.join(scratch.path, 'incoming.git');
    token = base64Url.encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    cancellation = calloc<ffi.Int32>();
    final working = path.join(scratch.path, 'working');
    await git(['init', '--initial-branch=main', working]);
    await git(['config', 'user.name', 'Transport fixture'], cwd: working);
    await git([
      'config',
      'user.email',
      'fixture@example.invalid',
    ], cwd: working);
    await File(path.join(working, 'SKILL.md')).writeAsString('fixture\n');
    await git(['add', '.'], cwd: working);
    await git(['commit', '-m', 'fixture'], cwd: working);
    parentCommit = await git(['rev-parse', 'HEAD'], cwd: working);
    await File(
      path.join(working, 'SKILL.md'),
    ).writeAsString('second revision\n');
    await git(['commit', '-am', 'second revision'], cwd: working);
    commit = await git(['rev-parse', 'HEAD'], cwd: working);
    await git(['clone', '--bare', working, source]);
    // Remove fixture clone provenance: the transport itself never writes it.
    await git(['config', '--remove-section', 'remote.origin'], cwd: source);
    await git(['init', '--bare', remote]);
    await git(['config', 'http.receivepack', 'true'], cwd: remote);
    await git(['init', '--bare', incoming]);
  });

  tearDown(() async {
    for (final backend in servers) {
      await backend.close();
    }
    servers.clear();
    calloc.free(cancellation);
    await scratch.delete(recursive: true);
  });

  test(
    'manual real-host probe uses the same formal shim and safe stdin/output',
    () async {
      final backend = await server();
      final probe = await Process.start(Platform.resolvedExecutable, [
        'run',
        'tool/qualify_repository_transport.dart',
      ]);
      final output = probe.stdout.transform(utf8.decoder).join();
      final errors = probe.stderr.transform(utf8.decoder).join();
      probe.stdin.writeln(
        jsonEncode({
          'remote': backend.locatorFor('remote.git'),
          'token': token,
          'fixturePath': scratch.path,
          'allowLoopbackHttpForTesting': true,
          'emitFixtureCommitId': true,
        }),
      );
      await probe.stdin.close();
      final code = await probe.exitCode;
      final stdout = await output;
      final stderr = await errors;
      expect(stdout, isNot(contains(token)));
      expect(stderr, isNot(contains(token)));
      final result =
          jsonDecode(const LineSplitter().convert(stdout).last)
              as Map<String, Object?>;
      expect(result['ok'], isTrue, reason: 'probe result: $result');
      expect(result['cleanup'], isTrue);
      expect(result['fixtureCommitId'], matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(code, 0);
    },
  );

  test(
    'authenticated push, exact retry, and complete-history fetch use formal shim',
    () async {
      final backend = await server();
      for (var attempt = 0; attempt < 2; attempt++) {
        final outcome = await push(backend);
        expect(outcome.status, RepositoryTransportStatus.ok);
        expect(outcome.refs, [RepositoryTransportRefStatus.accepted]);
      }
      expect(await git(['rev-parse', 'refs/heads/main'], cwd: remote), commit);
      final outcome = await native.fetchInto(
        repositoryPath: incoming,
        url: backend.locatorFor('remote.git'),
        refspecs: ['refs/heads/main:refs/transport/incoming'],
        customHeaders: ['Authorization: Bearer $token'],
        cancelFlagAddress: cancellation.address,
      );
      expect(outcome.status, RepositoryTransportStatus.ok);
      expect(outcome.refs, [RepositoryTransportRefStatus.accepted]);
      expect(
        await git(['rev-parse', 'refs/transport/incoming'], cwd: incoming),
        commit,
      );
      expect(
        await git(['cat-file', '-t', parentCommit], cwd: incoming),
        'commit',
      );
      expect(backend.authenticatedRequestCount, greaterThanOrEqualTo(4));
      await noPersistedAuth();
    },
  );

  test(
    'fetch preserves existing FETCH_HEAD and config; reflog contains no remote',
    () async {
      final backend = await server();
      expect((await push(backend)).status, RepositoryTransportStatus.ok);
      final fetchHead = File(path.join(incoming, 'FETCH_HEAD'));
      await fetchHead.writeAsString('preexisting fetch metadata\n');
      await git(['config', 'core.logAllRefUpdates', 'true'], cwd: incoming);
      final before = await File(path.join(incoming, 'config')).readAsBytes();
      final outcome = await native.fetchInto(
        repositoryPath: incoming,
        url: backend.locatorFor('remote.git'),
        refspecs: ['refs/heads/main:refs/heads/incoming'],
        customHeaders: ['Authorization: Bearer $token'],
        cancelFlagAddress: cancellation.address,
      );
      expect(outcome.status, RepositoryTransportStatus.ok);
      expect(await fetchHead.readAsString(), 'preexisting fetch metadata\n');
      expect(await File(path.join(incoming, 'config')).readAsBytes(), before);
      final reflog = await File(
        path.join(incoming, 'logs', 'refs', 'heads', 'incoming'),
      ).readAsString();
      expect(reflog, contains('object transfer'));
      expect(reflog, isNot(contains(token)));
      expect(reflog, isNot(contains(backend.locatorFor('remote.git'))));
      await fetchHead.delete();
      await noPersistedAuth();
    },
  );

  test(
    'per-ref rejection makes an otherwise successful push fail safely',
    () async {
      final hook = File(path.join(remote, 'hooks', 'update'));
      await hook.writeAsString(
        '#!/bin/sh\ncase "\$1" in *rejected) echo "secret server diagnostic" >&2; exit 1;; esac\nexit 0\n',
      );
      if (!Platform.isWindows) await Process.run('chmod', ['700', hook.path]);
      final outcome = await push(
        await server(),
        refspecs: [
          '$commit:refs/heads/accepted',
          '$commit:refs/heads/rejected',
        ],
      );
      expect(outcome.status, RepositoryTransportStatus.rejectedRef);
      expect(outcome.refs, [
        RepositoryTransportRefStatus.accepted,
        RepositoryTransportRefStatus.rejected,
      ]);
      expect(outcome.toString(), isNot(contains('secret server diagnostic')));
      await noPersistedAuth();
    },
  );

  test(
    'credentials are per operation; next anonymous operation fails authentication',
    () async {
      final backend = await server();
      expect((await push(backend)).status, RepositoryTransportStatus.ok);
      final outcome = await push(backend, headers: []);
      expect(outcome.status, RepositoryTransportStatus.authenticationRequired);
      expect(outcome.refs, [RepositoryTransportRefStatus.unreported]);
      await noPersistedAuth();
    },
  );

  test(
    'default HTTPS policy rejects HTTP, userinfo, queries, and header injection',
    () async {
      final backend = await server();
      final url = backend.locatorFor('remote.git');
      for (final value in [
        url,
        'https://user:secret@example.invalid/repo',
        'https://example.invalid/repo?token=secret',
        'https://example.invalid/repo#secret',
        'https://example.invalid/repo\u0000',
      ]) {
        expect(
          (await push(
            backend,
            transport: const RepositoryTransportNative(),
            url: value,
          )).status,
          RepositoryTransportStatus.invalidArgument,
        );
      }
      expect(
        (await push(
          backend,
          headers: ['Authorization: Bearer $token\r\nHost: attacker'],
        )).status,
        RepositoryTransportStatus.invalidArgument,
      );
      expect(backend.requestCount, 0);
    },
  );

  test(
    'redirects never forward operation headers to another endpoint',
    () async {
      final target = await server();
      final redirect = await server(
        redirectTo: target.locatorFor('remote.git'),
      );
      final outcome = await push(redirect);
      expect(outcome.status, isNot(RepositoryTransportStatus.ok));
      expect(redirect.requestCount, 1);
      expect(target.requestCount, 0);
    },
  );

  test(
    'repository URL rewrite config cannot redirect operation credentials',
    () async {
      final backend = await server();
      final target = await server();
      final configKey = 'url.${target.locatorFor('remote.git')}.insteadOf';
      await git([
        'config',
        configKey,
        backend.locatorFor('remote.git'),
      ], cwd: source);
      final before = await File(path.join(source, 'config')).readAsBytes();
      final outcome = await push(backend);
      expect(outcome.status, RepositoryTransportStatus.ok);
      expect(target.requestCount, 0);
      expect(backend.requestCount, greaterThan(0));
      expect(await File(path.join(source, 'config')).readAsBytes(), before);
      await git(['config', '--unset', configKey], cwd: source);
      await noPersistedAuth();
    },
  );

  test('same-host path redirects are refused before replay', () async {
    final backend = await server(redirectTo: '/other.git');
    final outcome = await push(backend);
    expect(outcome.status, isNot(RepositoryTransportStatus.ok));
    expect(backend.requestCount, 1);
  });

  test(
    'rejects force, wildcard, deletion, duplicate destinations, and missing refs',
    () async {
      final backend = await server();
      for (final specs in [
        ['+$commit:refs/heads/main'],
        ['refs/heads/*:refs/heads/*'],
        [':refs/heads/main'],
        ['$commit:refs/heads/main', '$commit:refs/heads/main'],
      ]) {
        expect(
          (await push(backend, refspecs: specs)).status,
          RepositoryTransportStatus.invalidArgument,
        );
      }
      expect(backend.requestCount, 0);
      final missing = await native.fetchInto(
        repositoryPath: incoming,
        url: backend.locatorFor('remote.git'),
        refspecs: ['refs/heads/missing:refs/transport/incoming'],
        customHeaders: ['Authorization: Bearer $token'],
        cancelFlagAddress: cancellation.address,
      );
      expect(missing.status, isNot(RepositoryTransportStatus.ok));
      expect(missing.refs, [RepositoryTransportRefStatus.unreported]);
    },
  );

  test(
    'pre-cancellation does not reach network or leak into another operation',
    () async {
      final backend = await server();
      cancellation.value = 1;
      expect((await push(backend)).status, RepositoryTransportStatus.cancelled);
      expect(backend.requestCount, 0);
      cancellation.value = 0;
      expect((await push(backend)).status, RepositoryTransportStatus.ok);
    },
  );

  test(
    'native progress callbacks cancel while push body is transferring',
    () async {
      final working = path.join(scratch.path, 'working');
      final random = Random(712);
      await File(path.join(working, 'large.bin')).writeAsBytes(
        List.generate(8 * 1024 * 1024, (_) => random.nextInt(256)),
      );
      await git(['add', '.'], cwd: working);
      await git(['commit', '-m', 'large fixture'], cwd: working);
      commit = await git(['rev-parse', 'HEAD'], cwd: working);
      await git([
        'fetch',
        working,
        'refs/heads/main:refs/heads/main',
      ], cwd: source);
      await File(path.join(source, 'FETCH_HEAD')).delete();
      var transferred = 0;
      final backend = await server(
        onRequestBody: (bytes) {
          transferred += bytes;
          cancellation.value = 1;
        },
      );
      final outcome = await push(backend);
      expect(transferred, greaterThan(0));
      expect(outcome.status, RepositoryTransportStatus.cancelled);
      expect(outcome.refs, [RepositoryTransportRefStatus.unreported]);
      await noPersistedAuth();
    },
  );

  test(
    'native callbacks observe cancellation after push discovery begins',
    () async {
      final backend = await server(onRequest: (_) => cancellation.value = 1);
      final outcome = await push(backend);
      expect(backend.requestCount, greaterThan(0));
      expect(outcome.status, RepositoryTransportStatus.cancelled);
      expect(outcome.refs, [RepositoryTransportRefStatus.unreported]);
      await noPersistedAuth();
    },
  );
}
