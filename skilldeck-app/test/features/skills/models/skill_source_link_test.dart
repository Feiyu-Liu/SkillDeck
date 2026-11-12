import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  SkillSourceLink link(
    String locator, [
    WorkspaceSourceKind kind = WorkspaceSourceKind.git,
  ]) => SkillSourceLink.fromSource(
    SkillSourceProvenance(kind: kind, locator: locator),
  );

  test('all nonempty kinds preserve the exact trimmed address for copying', () {
    for (final kind in WorkspaceSourceKind.values) {
      for (final address in [
        'https://github.com/owner/repo?tab=readme-ov-file#readme',
        'https://user:password@example.com/repo?token=secret#private',
        'git@github.com:owner/repo.git',
        'ssh://git@github.com/owner/repo.git',
        '/tmp/我的 skills:100%',
        'an opaque address',
      ]) {
        expect(link('  $address  ', kind).copyText, address);
      }
    }
  });

  test('local and adopted paths stay readable without requiring a URL', () {
    for (final kind in [
      WorkspaceSourceKind.local,
      WorkspaceSourceKind.adoptedSnapshot,
    ]) {
      for (final path in [
        '/tmp/我的 skills:100%',
        r'C:\Users\me\my skills',
        r'\\server\share\my skills',
        'adopted:opaque path 50%',
        'relative skills',
      ]) {
        expect(link(path, kind).label, path);
      }
    }
  });

  test('URL labels hide all credentials, queries and fragments', () {
    for (final kind in WorkspaceSourceKind.values) {
      final value = link(
        'https://user:password@example.com/repo?token=secret#private',
        kind,
      );
      expect(value.label, 'https://example.com/repo');
      expect(
        value.copyText,
        'https://user:password@example.com/repo?token=secret#private',
      );
    }
    expect(
      link('ssh://git@github.com/owner/repo.git').label,
      'ssh://github.com/owner/repo.git',
    );
    expect(
      link('git@github.com:owner/repo.git').label,
      'github.com:owner/repo.git',
    );
  });

  test('malformed credentials and control characters never enter labels', () {
    for (final address in [
      'https://user:password@[invalid/repo',
      'https://example.com/a\nb?token=secret',
    ]) {
      final value = link(address);
      expect(value.label, isEmpty);
      expect(value.copyText, address);
    }
  });

  test('empty and missing sources have no copy target', () {
    expect(SkillSourceLink.fromSource(null).copyText, isNull);
    expect(link('  ').copyText, isNull);
  });
}
