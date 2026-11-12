import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  SkillSourceLink link(
    String locator, {
    WorkspaceSourceKind kind = WorkspaceSourceKind.git,
  }) => SkillSourceLink.fromSource(
    SkillSourceProvenance(kind: kind, locator: locator),
  );

  test(
    'uses the exact webpage locator including resource path and safe query',
    () {
      for (final locator in [
        'https://github.com/owner/repo',
        'http://example.com/skills/alpha',
        'https://github.com/owner/repo?tab=readme-ov-file#readme',
      ]) {
        final value = link(locator);
        expect(value.uri.toString(), locator);
        expect(value.label, locator);
      }
    },
  );

  test(
    'removes credentials and sensitive or unknown query and fragment values',
    () {
      for (final locator in [
        'https://user:secret@example.com/repo',
        'https://example.com/repo?token=secret',
        'https://example.com/repo?signature=secret&tab=readme',
        'https://example.com/repo?unknown=secret',
        'https://example.com/repo#access_token=secret',
        'https://example.com/repo#opaquesecret',
        'https://example.com/repo?ref=secret',
        'ssh://user:secret@example.com/repo',
      ]) {
        final value = link(locator);
        expect(value.uri, isNull);
        expect(value.label, isNot(contains('secret')));
        expect(value.label, isNot(contains('user@')));
      }
    },
  );

  test('rejects control characters and backslashes in remote addresses', () {
    for (final locator in [
      'https://example.com/a\nb',
      r'https://example.com/a\b',
      'https://example.com/a b',
    ]) {
      expect(link(locator).uri, isNull);
    }
  });

  test(
    'local, SSH, invalid, and missing sources never invent a browser target',
    () {
      expect(
        link('/tmp/alpha', kind: WorkspaceSourceKind.local).label,
        '/tmp/alpha',
      );
      expect(
        link('git@github.com:owner/repo.git').label,
        'github.com:owner/repo.git',
      );
      for (final locator in [
        'git@github.com:owner/repo.git',
        'not a URL',
        'file:///tmp/alpha',
        'javascript:alert(1)',
        'https://',
      ]) {
        expect(link(locator).uri, isNull);
      }
      expect(SkillSourceLink.fromSource(null).uri, isNull);
    },
  );
}
