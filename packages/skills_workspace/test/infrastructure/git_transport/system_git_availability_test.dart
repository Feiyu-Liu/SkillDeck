import 'package:skills_workspace/src/infrastructure/git_transport/system_git_availability.dart';
import 'package:test/test.dart';

void main() {
  test('finds Git on a POSIX PATH without running it', () async {
    final availability = PathSystemGitAvailability(
      environment: const {'PATH': '/opt/homebrew/bin:/usr/bin'},
      isWindows: false,
      isMacOS: true,
      fileExists: (path) => path == '/opt/homebrew/bin/git',
      developerDirectory: () async => fail('the shim was consulted'),
    );
    expect(await availability.isAvailable(), isTrue);
  });

  test(
    'accepts the macOS shim only when developer tools provide Git',
    () async {
      Future<bool> check(String? developerDirectory, Set<String> files) =>
          PathSystemGitAvailability(
            environment: const {'PATH': '/usr/bin'},
            isWindows: false,
            isMacOS: true,
            fileExists: files.contains,
            developerDirectory: () async => developerDirectory,
          ).isAvailable();

      expect(
        await check('/Library/Developer/CommandLineTools\n', {
          '/usr/bin/git',
          '/Library/Developer/CommandLineTools/usr/bin/git',
        }),
        isTrue,
      );
      expect(await check(null, {'/usr/bin/git'}), isFalse);
      expect(
        await check('/Applications/Xcode.app/Contents/Developer', {
          '/usr/bin/git',
        }),
        isFalse,
      );
      expect(
        await PathSystemGitAvailability(
          environment: const {'PATH': '/usr/bin'},
          isWindows: false,
          isMacOS: true,
          fileExists: (path) => path == '/usr/bin/git',
          developerDirectory: () async => throw StateError('xcode-select'),
        ).isAvailable(),
        isFalse,
      );
    },
  );

  test('treats /usr/bin/git as real Git on Linux', () async {
    final availability = PathSystemGitAvailability(
      environment: const {'PATH': '/usr/local/bin:/usr/bin'},
      isWindows: false,
      isMacOS: false,
      fileExists: (path) => path == '/usr/bin/git',
    );
    expect(await availability.isAvailable(), isTrue);
  });

  test('finds git.exe on a Windows Path', () async {
    final availability = PathSystemGitAvailability(
      environment: const {
        'Path': r'C:\Windows\System32;C:\Program Files\Git\cmd',
      },
      isWindows: true,
      isMacOS: false,
      fileExists: (path) => path == r'C:\Program Files\Git\cmd\git.exe',
    );
    expect(await availability.isAvailable(), isTrue);
  });

  test('reports no Git when PATH is empty or missing', () async {
    for (final environment in const <Map<String, String>>[
      {},
      {'PATH': ''},
    ]) {
      final availability = PathSystemGitAvailability(
        environment: environment,
        isWindows: false,
        isMacOS: false,
        fileExists: (_) => true,
      );
      expect(await availability.isAvailable(), isFalse);
    }
  });
}
