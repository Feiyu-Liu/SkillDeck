import 'package:skills_workspace/src/infrastructure/git_transport/git_redaction.dart';
import 'package:test/test.dart';

void main() {
  test('redacts URL, query, token, and scp-style credentials', () {
    final diagnostic = redactGitDiagnostic(
      'https://user:secret@example.com/repo.git?token=private '
      'token=private user:secret@host:path',
    );

    expect(diagnostic, isNot(contains('user:secret')));
    expect(diagnostic, isNot(contains('token=private')));
    expect(diagnostic, contains('<redacted>'));
  });

  test('redacts the provided locator and bounds diagnostics', () {
    const locator = 'https://user:secret@example.com/repo.git?key=value';
    final diagnostic = redactGitDiagnostic(
      '$locator ${List.filled(5000, 'x').join()}',
      locator: locator,
    );

    expect(diagnostic, isNot(contains('user:secret')));
    expect(diagnostic, isNot(contains('key=value')));
    expect(diagnostic, endsWith('[truncated]'));
    expect(diagnostic.length, lessThan(4200));
  });

  test(
    'redacts a credential-bearing scp locator even when parsed as a URI',
    () {
      expect(
        redactGitLocator('user:secret@host.example:group/repo.git'),
        '<redacted>@host.example:group/repo.git',
      );
    },
  );
}
