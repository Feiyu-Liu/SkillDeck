@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/command_host/data/command_line_path_link_service.dart';

final class _RecordingRunner implements CommandLinePathLinkProcessRunner {
  _RecordingRunner([this.output = 'ok', this.onRun]);

  final String? output;
  final void Function()? onRun;
  final calls = <List<String>>[];

  @override
  Future<String?> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    onRun?.call();
    return output;
  }
}

void main() {
  late Directory temp;
  late String home;
  late String target;
  late String binDirectory;
  late String linkPath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-path-link-');
    home = p.join(temp.path, 'home');
    target = p.join(home, '.skilldeck', 'bin', 'skilldeck');
    await File(target).create(recursive: true);
    binDirectory = p.join(temp.path, 'usr-local-bin');
    await Directory(binDirectory).create();
    linkPath = p.join(binDirectory, 'skilldeck');
  });
  tearDown(() async {
    await Process.run('/bin/chmod', ['755', binDirectory]);
    await temp.delete(recursive: true);
  });

  MacOsCommandLinePathLink link({
    _RecordingRunner? runner,
    String? targetPath,
  }) => MacOsCommandLinePathLink(
    targetPath: targetPath ?? target,
    userHomePath: home,
    linkPath: linkPath,
    processRunner: runner ?? _RecordingRunner(),
  );

  Future<void> makeReadOnly() async => expect(
    (await Process.run('/bin/chmod', ['555', binDirectory])).exitCode,
    0,
  );

  group('status', () {
    test('is notInstalled when nothing is there', () async {
      expect(await link().status(), CommandLinePathLinkStatus.notInstalled);
    });

    test('is installed for a link to the stable copy, even dangling', () async {
      await Link(linkPath).create(target);
      await File(target).delete();
      expect(await link().status(), CommandLinePathLinkStatus.installed);
    });

    test('is a conflict for a file or a link elsewhere', () async {
      await File(linkPath).writeAsString('someone else');
      expect(await link().status(), CommandLinePathLinkStatus.conflict);
      await File(linkPath).delete();
      await Link(linkPath).create('/opt/other/skilldeck');
      expect(await link().status(), CommandLinePathLinkStatus.conflict);
    });
  });

  group('install', () {
    test('links directly when the directory is writable', () async {
      final runner = _RecordingRunner();
      expect(
        await link(runner: runner).install(),
        CommandLinePathLinkOutcome.succeeded,
      );
      expect(await Link(linkPath).target(), target);
      expect(runner.calls, isEmpty);
    });

    test('does nothing when already installed', () async {
      await Link(linkPath).create(target);
      final runner = _RecordingRunner();
      expect(
        await link(runner: runner).install(),
        CommandLinePathLinkOutcome.succeeded,
      );
      expect(runner.calls, isEmpty);
    });

    test('never replaces something else at the link path', () async {
      await File(linkPath).writeAsString('someone else');
      final runner = _RecordingRunner();
      expect(
        await link(runner: runner).install(),
        CommandLinePathLinkOutcome.conflict,
      );
      expect(await File(linkPath).readAsString(), 'someone else');
      expect(runner.calls, isEmpty);
    });

    test(
      'elevates through osascript when the directory is not writable',
      () async {
        await makeReadOnly();
        final runner = _RecordingRunner('ok\n', () {
          // Stand in for the privileged ln.
          Process.runSync('/bin/chmod', ['755', binDirectory]);
          Link(linkPath).createSync(target);
        });
        expect(
          await link(runner: runner).install(),
          CommandLinePathLinkOutcome.succeeded,
        );
        expect(runner.calls.single.first, '/usr/bin/osascript');
        expect(runner.calls.single.sublist(3), [
          '--',
          'install',
          target,
          linkPath,
          binDirectory,
        ]);
      },
    );

    test('maps a cancelled password prompt and a failure', () async {
      await makeReadOnly();
      expect(
        await link(runner: _RecordingRunner('cancelled')).install(),
        CommandLinePathLinkOutcome.cancelled,
      );
      expect(
        await link(runner: _RecordingRunner('failed')).install(),
        CommandLinePathLinkOutcome.failed,
      );
      expect(
        await link(runner: _RecordingRunner(null)).install(),
        CommandLinePathLinkOutcome.failed,
      );
    });

    test('never elevates for a target outside the home', () async {
      await makeReadOnly();
      final runner = _RecordingRunner();
      expect(
        await link(runner: runner, targetPath: '/tmp/skilldeck').install(),
        CommandLinePathLinkOutcome.failed,
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('remove', () {
    test('removes only SkillDeck’s own link', () async {
      await Link(linkPath).create(target);
      expect(await link().remove(), CommandLinePathLinkOutcome.succeeded);
      expect(
        await FileSystemEntity.type(linkPath, followLinks: false),
        FileSystemEntityType.notFound,
      );
    });

    test('leaves something else in place', () async {
      await File(linkPath).writeAsString('someone else');
      final runner = _RecordingRunner();
      expect(
        await link(runner: runner).remove(),
        CommandLinePathLinkOutcome.conflict,
      );
      expect(await File(linkPath).readAsString(), 'someone else');
      expect(runner.calls, isEmpty);
    });

    test('elevates when the directory is not writable', () async {
      await Link(linkPath).create(target);
      await makeReadOnly();
      final runner = _RecordingRunner('ok', () {
        Process.runSync('/bin/chmod', ['755', binDirectory]);
        Link(linkPath).deleteSync();
      });
      expect(
        await link(runner: runner).remove(),
        CommandLinePathLinkOutcome.succeeded,
      );
      expect(runner.calls.single[4], 'remove');
    });
  });
}
