import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_repository_groups.dart';

SkillSourceProvenance source(
  String locator, {
  String? ref,
  String subpath = '',
}) => SkillSourceProvenance(
  kind: WorkspaceSourceKind.git,
  locator: locator,
  ref: ref,
  repositorySubpath: subpath,
  skillPath: '$subpath/SKILL.md',
);
InstalledSkill skill(String name, String locator, {DateTime? date}) =>
    InstalledSkill(
      id: WorkspaceSkillId(name),
      slotKey: name,
      displayName: name,
      description: '',
      contentHash: 'same',
      activationCount: 0,
      createdAt: date,
      source: source(locator),
    );

void main() {
  test('HTTPS SSH SCP and default ports share GitHub identity and ignore selections', () {
    final identities = [
      source('https://GitHub.com/Owner/Repo.git/'),
      source('ssh://alice@github.com:22/owner/repo', ref: 'next', subpath: 'a'),
      source('git@github.com:OWNER/REPO.git', ref: 'main', subpath: 'b'),
      source('https://github.com:443/owner/repo'),
      source('http://github.com:80/owner/repo'),
    ].map(repositoryIdentity).toList();
    expect(identities.map((e) => e.key).toSet(), hasLength(1));
    expect(identities.first.title, 'owner/repo');
    expect(identities.first.host, 'github.com');
  });
  test('owner host nondefault port and full GitLab subgroup stay distinct', () {
    final locators = [
      'https://gitlab.com/team/sub/Repo.git',
      'https://gitlab.com/team/sub/repo.git',
      'https://gitlab.com/team/other/repo.git',
      'https://elsewhere.test/team/sub/repo.git',
      'ssh://git@gitlab.com:2222/team/sub/repo.git',
    ];
    expect(
      locators.map((e) => repositoryIdentity(source(e)).key).toSet(),
      hasLength(5),
    );
    expect(repositoryIdentity(source(locators.first)).title, 'team/sub/Repo');
    expect(repositoryIdentity(source(locators.last)).host, 'gitlab.com:2222');
  });
  test(
    'local Git uses normalized full path and supports spaces and Windows paths',
    () {
      final a = repositoryIdentity(source('/work/My Repo/../Repo/'));
      final b = repositoryIdentity(source('file:///work/Repo'));
      expect(a.key, b.key);
      expect(a.title, 'Repo');
      expect(a.tooltip, '/work/Repo');
      expect(
        repositoryIdentity(source(r'C:\work\repo')).tooltip,
        r'C:\work\repo',
      );
      expect(repositoryIdentity(source('/work/My Repo')).title, 'My Repo');
      expect(repositoryIdentity(source('/else/Repo')).key, isNot(a.key));
    },
  );
  test('decoded local file controls never enter group display identity', () {
    for (final locator in [
      'file:///work/repo%0Asecret',
      'file:///work/%00repo',
    ]) {
      final identity = repositoryIdentity(source(locator));
      expect(identity.key, 'fallback:unknown', reason: locator);
      expect(identity.title, isEmpty);
      expect(identity.tooltip, isNull);
    }
  });

  test('Unicode encoded names IPv6 and UNC provenance stay representable', () {
    expect(
      repositoryIdentity(
        source('https://git.example/team/%E6%8A%80%E8%83%BD.git'),
      ).title,
      'team/技能',
    );
    expect(
      repositoryIdentity(source('ssh://git@[2001:db8::1]:2222/team/repo')).host,
      '[2001:db8::1]:2222',
    );
    expect(repositoryIdentity(source(r'\\server\share\repo')).title, 'repo');
    expect(
      repositoryIdentity(source('/work/Repo?#1')).tooltip,
      '/work/Repo?#1',
    );
    expect(
      repositoryIdentity(source('file://localhost/work/repo')).bucket,
      SkillRepositoryBucket.repository,
    );
    for (final kind in WorkspaceSourceKind.values) {
      expect(
        repositoryIdentity(SkillSourceProvenance(kind: kind, locator: ''))
            .bucket,
        SkillRepositoryBucket.unknown,
      );
    }
  });
  test(
    'non Git sources use fixed buckets and malformed locators reveal nothing',
    () {
      for (final kind in WorkspaceSourceKind.values.where(
        (e) => e != WorkspaceSourceKind.git,
      )) {
        final identity = repositoryIdentity(
          SkillSourceProvenance(
            kind: kind,
            locator:
                'https://secret:password@example.test/private?token=hidden',
          ),
        );
        expect(
          identity.key,
          kind == WorkspaceSourceKind.wellKnown
              ? 'fallback:web'
              : 'fallback:local',
        );
        expect(identity.tooltip, isNull);
      }
      for (final value in [
        '',
        'user:secret@example.com:team/repo',
        'git:password@host:repo',
        'user%3Asecret@example.com:team/repo',
        'user:secret%40example.com:team/repo',
        'relative/path',
        'https://secret:password@example.test/a/b',
        'ssh://secret:password@example.test/a/b',
        'ssh://secret%3Apassword@example.test/a/b',
        'https://example.test/a/b?token=hidden',
        'https://example.test/a/b#secret',
        'https://example.test/a/%2e%2e/b',
        'https://example.test/a//b',
        'https://example.test:99999/a/b',
        'https://example.test',
        'https://example.test/a/../b',
        'file://secret@localhost/work/repo',
        'https://example.test/a\nb',
        'https://[broken',
      ]) {
        final identity = repositoryIdentity(source(value));
        expect(identity.key, 'fallback:unknown', reason: value);
        expect(identity.title, isEmpty);
        expect(identity.tooltip, isNull);
      }
      expect(repositoryIdentity(null).bucket, SkillRepositoryBucket.unknown);
    },
  );
  test('groups preserve all four member sorts, original objects and group A-Z order', () {
    final members = [
      skill('Zed', 'https://github.com/b/repo', date: DateTime(2026)),
      skill('Beta', 'https://github.com/a/repo', date: DateTime(2025)),
      skill('Alpha', 'https://github.com/a/repo', date: DateTime(2024)),
    ];
    for (final mode in SkillListSortMode.values) {
      final sorted = [...members]
        ..sort((a, b) => compareInstalledSkills(a, b, mode));
      final groups = groupSkillsByRepository(sorted);
      expect(groups.map((e) => e.identity.title), ['a/repo', 'b/repo']);
      expect(
        groups.first.skills,
        orderedEquals(sorted.where((e) => e != members.first)),
      );
      expect(
        identical(
          groups.first.skills.first,
          sorted.firstWhere((e) => e != members.first),
        ),
        isTrue,
      );
    }
    final filtered = groupSkillsByRepository([members.last]);
    expect(filtered, hasLength(1));
    expect(filtered.single.skills, hasLength(1));
    expect(groupSkillsByRepository([]), isEmpty);
  });
  test('source replacement with same Skill identity and hash is regrouped', () {
    final before = skill('A', 'https://github.com/a/first');
    final after = skill('A', 'https://github.com/b/second');
    expect(
      before,
      after,
    ); // InstalledSkill equality intentionally omits source.
    expect(
      groupSkillsByRepository([before]).single.identity.key,
      isNot(groupSkillsByRepository([after]).single.identity.key),
    );
    expect(
      identical(
        groupSkillsByRepository([after]).single.skills.single.source,
        after.source,
      ),
      isTrue,
    );
  });
  test('fallback buckets follow repositories in local web unknown order', () {
    InstalledSkill fallback(String id, WorkspaceSourceKind? kind) =>
        InstalledSkill(
          id: WorkspaceSkillId(id),
          slotKey: id,
          displayName: id,
          description: '',
          contentHash: '',
          activationCount: 0,
          source: kind == null
              ? null
              : SkillSourceProvenance(kind: kind, locator: '/source'),
        );
    expect(
      groupSkillsByRepository([
        fallback('unknown', null),
        fallback('web', WorkspaceSourceKind.wellKnown),
        fallback('local', WorkspaceSourceKind.local),
        skill('git', 'https://github.com/a/z'),
        fallback('adopted', WorkspaceSourceKind.adoptedSnapshot),
      ]).map((e) => e.identity.bucket),
      SkillRepositoryBucket.values,
    );
  });
}
