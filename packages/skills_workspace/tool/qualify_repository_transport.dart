import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/native/repository_transport/repository_transport_native.dart';

/// Manual real-host qualification. Supply JSON {remote, token} on stdin only.
/// No input, URLs, headers, server diagnostics, or fixture bytes are printed.
Future<void> main() async {
  Directory? scratch;
  final cancel = calloc<ffi.Int32>();
  final transferred = calloc<ffi.Int64>();
  Timer? cancelWhenTransferred;
  Timer? deadline;
  final result = <String, Object?>{'ok': false};
  var phase = 'input';
  try {
    final input = jsonDecode(await stdin.transform(utf8.decoder).join());
    if (input is! Map<String, Object?> ||
        input['remote'] is! String ||
        input['token'] is! String) {
      throw const FormatException();
    }
    final remote = input['remote']! as String;
    final token = input['token']! as String;
    if (token.isEmpty || RegExp(r'[\x00-\x20\x7f]').hasMatch(token)) {
      throw const FormatException();
    }
    phase = 'fixture';
    final parent = input['fixturePath'];
    scratch = parent is String
        ? await Directory(parent).createTemp('transport-qualification-')
        : await Directory.systemTemp.createTemp('transport-qualification-');
    final working = path.join(scratch.path, 'working');
    final source = path.join(scratch.path, 'source.git');
    final incoming = path.join(scratch.path, 'incoming.git');
    await _git(['init', '--initial-branch=main', working]);
    await _git([
      'config',
      'user.name',
      'Transport qualification',
    ], cwd: working);
    await _git([
      'config',
      'user.email',
      'qualification@example.invalid',
    ], cwd: working);
    await File(path.join(working, 'SKILL.md')).writeAsString(
      '---\nname: transport-qualification\ndescription: Temporary fixture\n---\nFixture.\n',
    );
    await _git(['add', '.'], cwd: working);
    await _git(['commit', '-m', 'qualification'], cwd: working);
    final commit = await _git(['rev-parse', 'HEAD'], cwd: working);
    if (input['emitFixtureCommitId'] == true) {
      result['fixtureCommitId'] = commit;
    }
    await _git(['clone', '--bare', working, source]);
    await _git(['config', '--remove-section', 'remote.origin'], cwd: source);
    await _git(['init', '--bare', incoming]);
    final native = RepositoryTransportNative(
      allowLoopbackHttpForTesting: input['allowLoopbackHttpForTesting'] == true,
    );
    final headers = ['Authorization: Bearer $token'];
    final target = 'refs/skilldeck/commits/$commit';
    phase = 'push';
    final push = await native.push(
      repositoryPath: source,
      url: remote,
      refspecs: ['$commit:$target'],
      customHeaders: headers,
      cancelFlagAddress: cancel.address,
      progressBytesAddress: transferred.address,
    );
    result['push'] = {
      'status': push.status.name,
      'refs': push.refs.map((value) => value.name).toList(),
      'transferred': transferred.value > 0,
    };
    phase = 'fetch';
    final fetch = await native.fetchInto(
      repositoryPath: incoming,
      url: remote,
      refspecs: ['$target:refs/qualification/incoming'],
      customHeaders: headers,
      cancelFlagAddress: cancel.address,
      progressBytesAddress: transferred.address,
    );
    final matches =
        fetch.status.name == 'ok' &&
        await _git([
              'rev-parse',
              'refs/qualification/incoming',
            ], cwd: incoming) ==
            commit;
    result['fetch'] = {
      'status': fetch.status.name,
      'refs': fetch.refs.map((value) => value.name).toList(),
      'objectMatches': matches,
    };
    phase = 'cancellationFixture';
    final random = Random.secure();
    await File(
      path.join(working, 'cancel.bin'),
    ).writeAsBytes(List.generate(8 * 1024 * 1024, (_) => random.nextInt(256)));
    await _git(['add', '.'], cwd: working);
    await _git(['commit', '-m', 'cancellation fixture'], cwd: working);
    final cancelCommit = await _git(['rev-parse', 'HEAD'], cwd: working);
    await _git([
      'fetch',
      working,
      'refs/heads/main:refs/heads/main',
    ], cwd: source);
    await File(path.join(source, 'FETCH_HEAD')).delete();
    transferred.value = 0;
    var cancelledAfterProgress = false;
    cancelWhenTransferred = Timer.periodic(const Duration(milliseconds: 1), (
      timer,
    ) {
      if (transferred.value > 0) {
        cancelledAfterProgress = true;
        cancel.value = 1;
        timer.cancel();
      }
    });
    // A deadline only requests cancellation; memory stays owned until the
    // native worker actually returns, including on a stalled connection.
    deadline = Timer(const Duration(minutes: 2), () => cancel.value = 1);
    phase = 'cancel';
    final cancelled = await native.push(
      repositoryPath: source,
      url: remote,
      refspecs: ['$cancelCommit:refs/skilldeck/commits/$cancelCommit'],
      customHeaders: headers,
      cancelFlagAddress: cancel.address,
      progressBytesAddress: transferred.address,
    );
    cancelWhenTransferred.cancel();
    deadline.cancel();
    result['cancel'] = {
      'status': cancelled.status.name,
      'refs': cancelled.refs.map((value) => value.name).toList(),
      'cancelledAfterTransferBytes': cancelledAfterProgress,
    };
    phase = 'persistence';
    var isolated = true;
    for (final repository in [source, incoming]) {
      for (final entity in Directory(repository).listSync(recursive: true)) {
        if (entity is! File) continue;
        final value = latin1.decode(await entity.readAsBytes());
        if (value.contains(token) || value.contains(remote)) isolated = false;
      }
      if (await File(path.join(repository, 'FETCH_HEAD')).exists()) {
        isolated = false;
      }
      final config = await File(path.join(repository, 'config')).readAsString();
      if (config.contains('[remote ')) isolated = false;
    }
    result['noPersistedAuthOrRemote'] = isolated;
    result['ok'] =
        push.status.name == 'ok' &&
        matches &&
        cancelled.status.name == 'cancelled' &&
        cancelledAfterProgress &&
        isolated;
  } on Object {
    // Deliberately do not print exception.toString(), native errors or input.
    result['failure'] = 'qualificationFailed';
    result['phase'] = phase;
  } finally {
    cancelWhenTransferred?.cancel();
    deadline?.cancel();
    calloc.free(cancel);
    calloc.free(transferred);
    try {
      if (scratch != null) await scratch.delete(recursive: true);
      result['cleanup'] = true;
    } on Object {
      result['cleanup'] = false;
      result['ok'] = false;
    }
  }
  stdout.writeln(jsonEncode(result));
  if (result['ok'] != true) exitCode = 1;
}

Future<String> _git(List<String> arguments, {String? cwd}) async {
  final process = await Process.run('git', arguments, workingDirectory: cwd);
  if (process.exitCode != 0) throw const FormatException();
  return (process.stdout as String).trim();
}
