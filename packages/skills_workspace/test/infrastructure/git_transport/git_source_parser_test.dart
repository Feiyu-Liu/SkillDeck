// Portions derived from vercel-labs/skills (MIT), Copyright (c) 2026 Vercel, Inc. See THIRD_PARTY_NOTICES.md.
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_parser.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:test/test.dart';

void main() {
  const parser = GitSourceParser();

  test('resolves GitHub shorthand, ref, subpath, and Skill selection', () {
    final result = parser.parseWithSelection(
      'github:owner/repo/path/to/skills#feature%2Ftopic@writer',
    );
    final parsed = result.valueOrNull!;

    expect(parsed.descriptor.locator, 'https://github.com/owner/repo.git');
    expect(parsed.descriptor.ref, 'feature/topic');
    expect(parsed.descriptor.repositorySubpath, 'path/to/skills');
    expect(parsed.skillFilter, 'writer');
  });

  test('resolves GitHub tree URL using the first ref segment', () {
    final result = parser.parse(
      'https://github.com/owner/repo/tree/feature/path/to/skill',
    );
    final descriptor = result.valueOrNull!;

    expect(descriptor.locator, 'https://github.com/owner/repo.git');
    expect(descriptor.ref, 'feature');
    expect(descriptor.repositorySubpath, 'path/to/skill');
  });

  test('resolves GitLab subgroup and custom-host tree URLs', () {
    final prefix = parser.parse('gitlab:group/subgroup/repo');
    expect(
      prefix.valueOrNull!.locator,
      'https://gitlab.com/group/subgroup/repo.git',
    );

    final tree = parser.parse(
      'https://git.example.com/group/repo/-/tree/main/skills/review',
    );
    expect(tree.valueOrNull!.locator, 'https://git.example.com/group/repo.git');
    expect(tree.valueOrNull!.ref, 'main');
    expect(tree.valueOrNull!.repositorySubpath, 'skills/review');
  });

  test('preserves generic HTTPS, SSH URI, and scp-style locators', () {
    expect(
      parser
          .parse('https://code.example.com/group/repo.git')
          .valueOrNull!
          .locator,
      'https://code.example.com/group/repo.git',
    );
    expect(
      parser
          .parse('ssh://git@code.example.com/group/repo.git')
          .valueOrNull!
          .locator,
      'ssh://git@code.example.com/group/repo.git',
    );
    expect(
      parser.parse('git@code.example.com:group/repo.git').valueOrNull!.locator,
      'git@code.example.com:group/repo.git',
    );
  });

  test('accepts a normalized absolute local repository path', () {
    final descriptor = parser.parse('/tmp/repositories/repo.git').valueOrNull!;

    expect(descriptor.locator, '/tmp/repositories/repo.git');
    expect(descriptor.ref, isNull);
  });

  test(
    'rejects unsupported transports, traversal, queries, and credentials',
    () {
      final cases = <String, String>{
        'ext::helper command': 'unsupportedTransport',
        'file:///tmp/repo.git': 'unsupportedTransport',
        'github:owner/repo/../secret': 'invalidRepositorySubpath',
        'https://example.com/repo.git?token=secret': 'embeddedCredentials',
        'https://user:secret@example.com/repo.git': 'embeddedCredentials',
        'user:secret@code.example.com:group/repo.git': 'embeddedCredentials',
      };

      for (final entry in cases.entries) {
        final failure = parser.parse(entry.key).failureOrNull!;
        expect(failure.code, GitTransportFailureCode.rejected);
        expect(failure.context['reason'], entry.value, reason: entry.key);
      }
    },
  );
}
