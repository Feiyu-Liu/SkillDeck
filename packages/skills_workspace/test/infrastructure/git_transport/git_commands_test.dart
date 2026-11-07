import 'dart:convert';

import 'package:skills_workspace/src/infrastructure/git_transport/git_commands.dart';
import 'package:test/test.dart';

void main() {
  const environmentPolicy = GitEnvironmentPolicy();
  const builder = GitBareCommandBuilder();
  const repositoryPath = '/tmp/source.git';
  const disabledHooksPath = '/tmp/empty-hooks';
  const objectId = '0123456789abcdef0123456789abcdef01234567';

  test('non-interactive policy overrides prompts but preserves SSH access', () {
    final environment = environmentPolicy.apply(const {
      'GIT_SSH_COMMAND': 'custom-ssh -F /tmp/config',
      'SSH_AUTH_SOCK': '/tmp/agent.sock',
      'GIT_TERMINAL_PROMPT': '1',
      'GCM_INTERACTIVE': 'Always',
      'GIT_LFS_SKIP_SMUDGE': '0',
      'SSH_ASKPASS_REQUIRE': 'force',
    });

    expect(environment['GIT_SSH_COMMAND'], 'custom-ssh -F /tmp/config');
    expect(environment['SSH_AUTH_SOCK'], '/tmp/agent.sock');
    expect(environment['GIT_TERMINAL_PROMPT'], '0');
    expect(environment['GCM_INTERACTIVE'], 'Never');
    expect(environment['GIT_LFS_SKIP_SMUDGE'], '1');
    expect(environment['SSH_ASKPASS_REQUIRE'], 'never');
  });

  test('builds only bare init and hardened fetch argv', () {
    final initialize = builder.initialize(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      environment: const {},
    );
    expect(initialize.arguments, [
      '-c',
      'init.templateDir=$disabledHooksPath',
      'init',
      '--bare',
      '--',
      repositoryPath,
    ]);

    final fetch = builder.fetch(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      locator: 'git@code.example.com:group/repo.git',
      ref: '--opaque/value',
      environment: const {},
    );
    expect(fetch.arguments, [
      '-C',
      repositoryPath,
      '-c',
      'core.hooksPath=$disabledHooksPath',
      '-c',
      'filter.lfs.required=false',
      '-c',
      'filter.lfs.smudge=',
      '-c',
      'filter.lfs.clean=',
      '-c',
      'filter.lfs.process=',
      'fetch',
      '--depth',
      '1',
      '--no-tags',
      '--recurse-submodules=no',
      '--',
      'git@code.example.com:group/repo.git',
      '--opaque/value',
    ]);
    expect(fetch.arguments, isNot(contains('clone')));
    expect(fetch.arguments, isNot(contains('checkout')));
  });

  test('builds resolve, recursive ls-tree, and cat-file batch commands', () {
    final resolve = builder.resolveFetchedCommit(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      environment: const {},
    );
    expect(
      resolve.arguments,
      containsAllInOrder(['rev-parse', '--verify', 'FETCH_HEAD^{commit}']),
    );

    final tree = builder.listTree(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      objectId: objectId,
      repositorySubpath: 'skills/review',
      environment: const {},
    );
    expect(
      tree.arguments,
      containsAllInOrder([
        'ls-tree',
        '-r',
        '-rz',
        '--full-tree',
        objectId,
        '--',
        'skills/review',
      ]),
    );

    final batch = builder.catFileBatch(
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      environment: const {},
      objectIds: const [objectId],
    );
    expect(batch.arguments, containsAllInOrder(['cat-file', '--batch']));
    expect(utf8.decode(batch.stdinBytes), '$objectId\n');
  });

  test('builds platform helper commands as argv without shell syntax', () {
    final windows = GitProcessTreeCommands.windowsTaskkill(42);
    expect(windows.executable, 'taskkill');
    expect(windows.arguments, ['/PID', '42', '/T', '/F']);

    final posix = GitProcessTreeCommands.posixProcessTable();
    expect(posix.executable, 'ps');
    expect(posix.arguments, ['-eo', 'pid=,ppid=']);
    expect(
      [...windows.arguments, ...posix.arguments].join(' '),
      isNot(contains('&&')),
    );
  });

  test('rejects untrusted object IDs and repository subpaths', () {
    expect(
      () => builder.listTree(
        repositoryPath: repositoryPath,
        disabledHooksPath: disabledHooksPath,
        objectId: '--help',
        environment: const {},
      ),
      throwsArgumentError,
    );
    expect(
      () => builder.listTree(
        repositoryPath: repositoryPath,
        disabledHooksPath: disabledHooksPath,
        objectId: objectId,
        repositorySubpath: '../escape',
        environment: const {},
      ),
      throwsArgumentError,
    );
  });
}
