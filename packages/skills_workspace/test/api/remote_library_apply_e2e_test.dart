import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';

void main() {
  late DriftFacadeFixture fixture;
  late SkillsRepository repository;
  late ManagedSkillId skillId;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(activate: false);
    repository = fixture.repository;
    skillId = fixture.managedSkillId;
  });

  Future<RevisionId> effective() async => (await driftSuccess(
    repository.inspectRevisionSelections(
      InspectRevisionSelectionsRequest(managedSkillIds: {skillId}),
    ),
  )).selections[skillId]!.effective;

  Future<CommittedChangesAvailable> feed(RepositoryRevision since) async =>
      await driftSuccess(
            repository.inspectCommittedChanges(
              InspectCommittedChangesRequest(since: since),
            ),
          )
          as CommittedChangesAvailable;

  Future<List<OperationId>> operationHistory() async => [
    for (final entry in (await driftSuccess(
      repository.inspectOperationHistory(const OperationHistoryRequest()),
    )).entries)
      entry.operationId,
  ];

  Future<void> expectOneCommit(
    RepositoryRevision since, {
    bool vocabularyChanged = false,
    Set<ManagedSkillId> metadata = const {},
  }) async {
    final changes = await feed(since);
    expect(changes.current, since.next());
    expect(repository.snapshot.revision, changes.current);
    expect(changes.vocabularyChanged, vocabularyChanged);
    expect(changes.entries, hasLength(metadata.length));
    expect(
      changes.entries.map((entry) => entry.managedSkillId),
      unorderedEquals(metadata),
    );
    for (final entry in changes.entries) {
      expect(entry.kinds, {CommittedChangeKind.metadata});
      expect(entry.revision, changes.current);
    }
  }

  Future<void> expectNoCommit(
    RepositorySnapshot before,
    List<OperationId> historyBefore,
  ) async {
    expect(repository.snapshot, before);
    expect(await operationHistory(), historyBefore);
    final changes = await feed(before.revision);
    expect(changes.current, before.revision);
    expect(changes.entries, isEmpty);
    expect(changes.vocabularyChanged, isFalse);
  }

  Future<RemoteApplyResult> apply(ApplyRemoteStateRequest request) =>
      driftSuccess(repository.applyRemoteState(request));

  Future<String> applyTag(RemoteTagVocabulary request) async {
    final result = await apply(request);
    expect(result, isA<RemoteApplyTag>());
    return (result as RemoteApplyTag).tagId;
  }

  Future<String> ensure(String name, String? color) =>
      applyTag(RemoteTagVocabulary.ensure(name: name, color: color));

  Future<String> localTag(String name) async => (await driftSuccess(
    repository.createPersonalTag(CreatePersonalTagRequest(name: name)),
  )).id;

  Future<void> assign(ManagedSkillId id, String tagId) => driftSuccess(
    repository.assignPersonalTag(
      AssignPersonalTagRequest(managedSkillId: id, tagId: tagId),
    ),
  );

  ManagedSkill skill() => repository.snapshot.findSkill(skillId)!;

  group('remote metadata', () {
    test(
      'sets final values together and repeats without another commit',
      () async {
        final work = await localTag('Work');
        final home = await localTag('Home');
        final expected = await effective();
        final request = RemoteSkillMetadata(
          managedSkillId: skillId,
          expectedEffective: expected,
          favorite: true,
          note: '  Remember this  ',
          tagIds: {work, home},
        );
        final before = repository.snapshot.revision;

        expect(await apply(request), isA<RemoteApplyMetadataApplied>());
        expect(skill().favorite.isFavorite, isTrue);
        expect(skill().note?.text, 'Remember this');
        expect(skill().personalTagIds, unorderedEquals([work, home]));
        expect(await effective(), expected);
        await expectOneCommit(before, metadata: {skillId});

        final applied = repository.snapshot;
        final history = await operationHistory();
        expect(await apply(request), isA<RemoteApplyNoChange>());
        await expectNoCommit(applied, history);

        expect(
          await apply(
            RemoteSkillMetadata(
              managedSkillId: skillId,
              expectedEffective: expected,
              favorite: false,
              note: null,
              tagIds: {home},
            ),
          ),
          isA<RemoteApplyMetadataApplied>(),
        );
        expect(skill().favorite.isFavorite, isFalse);
        expect(skill().note, isNull);
        expect(skill().personalTagIds, [home]);
        await expectOneCommit(applied.revision, metadata: {skillId});
      },
    );

    test(
      'checks the Effective guard before tags and rejects invalid metadata',
      () async {
        final expected = await effective();
        RemoteSkillMetadata request(RevisionId revision, String note) =>
            RemoteSkillMetadata(
              managedSkillId: skillId,
              expectedEffective: revision,
              favorite: true,
              note: note,
              tagIds: {'missing-tag'},
            );
        expect(() => request(expected, ' \t\n'), throwsArgumentError);

        final before = repository.snapshot;
        await driftFailure(
          repository.applyRemoteState(request(RevisionId('0' * 40), 'A note')),
          SkillsErrorCode.staleSnapshot,
          reason: 'effectiveRevisionChanged',
        );
        expect(repository.snapshot, before);
        await driftFailure(
          repository.applyRemoteState(request(expected, 'A note')),
          SkillsErrorCode.personalTagNotFound,
        );
        expect(repository.snapshot, before);
        expect((await feed(before.revision)).entries, isEmpty);
      },
    );

    for (final candidateOpen in [false, true]) {
      test(
        'applies with ${candidateOpen ? 'an Update Candidate Session' : 'a Dirty Draft'}',
        () async {
          final draft = await driftSuccess(
            repository.ensureDraft(EnsureDraftRequest(managedSkillId: skillId)),
          );
          await fixture.changeNotes(draft.path, 'local draft edit\n');
          if (candidateOpen) {
            await driftSuccess(
              repository.publishDraft(
                PublishDraftRequest(managedSkillId: skillId),
              ),
            );
            await fixture.changeNotes(fixture.sourcePath, 'upstream edit\n');
            await driftSuccess(
              repository.update(UpdateRequest(managedSkillIds: {skillId})),
            );
            expect(
              skill().updateCandidate?.status,
              UpdateCandidateStatus.conflicted,
            );
          } else {
            final currentDraft = await driftSuccess(
              repository.inspectDraft(
                InspectDraftRequest(managedSkillId: skillId),
              ),
            );
            expect(currentDraft?.isDirty, isTrue);
          }
          final before = repository.snapshot.revision;
          final expected = await effective();
          expect(
            await apply(
              RemoteSkillMetadata(
                managedSkillId: skillId,
                expectedEffective: expected,
                favorite: true,
                note: 'changed',
                tagIds: {},
              ),
            ),
            isA<RemoteApplyMetadataApplied>(),
          );
          expect(skill().note?.text, 'changed');
          expect(await effective(), expected);
          if (candidateOpen) {
            expect(
              skill().updateCandidate?.status,
              UpdateCandidateStatus.conflicted,
            );
          } else {
            expect(
              await File(path.join(draft.path, 'notes.md')).readAsString(),
              'local draft edit\n',
            );
          }
          await expectOneCommit(before, metadata: {skillId});
        },
      );
    }
  });

  group('remote vocabulary', () {
    test(
      'ensures one normalized identity with the final display name and color',
      () async {
        final start = repository.snapshot.revision;
        final tagId = await ensure('Work', '#112233');
        (String, String, String?) tagValues() {
          final tag = repository.snapshot.personalTags.single;
          return (tag.id, tag.name, tag.color);
        }

        expect(tagValues(), (tagId, 'Work', '#112233'));
        await expectOneCommit(start, vocabularyChanged: true);

        final beforeRepeat = repository.snapshot;
        final history = await operationHistory();
        expect(await ensure('Work', '#112233'), tagId);
        await expectNoCommit(beforeRepeat, history);

        final beforeRename = repository.snapshot.revision;
        expect(await ensure('  WORK  ', '#112233'), tagId);
        expect(tagValues(), (tagId, 'WORK', '#112233'));
        await expectOneCommit(beforeRename, vocabularyChanged: true);

        for (final color in ['#aabbcc', null]) {
          final beforeColor = repository.snapshot.revision;
          expect(await ensure('WORK', color), tagId);
          expect(tagValues(), (tagId, 'WORK', color));
          await expectOneCommit(beforeColor, vocabularyChanged: true);
        }
      },
    );

    test(
      'updates color without changing assignments and rejects invalid color',
      () async {
        final tagId = await localTag('Work');
        await assign(skillId, tagId);
        expect(
          () => RemoteTagVocabulary.update(
            tagId: tagId,
            name: 'Work',
            color: '#abc',
          ),
          throwsArgumentError,
        );
        final before = repository.snapshot.revision;
        final request = RemoteTagVocabulary.update(
          tagId: tagId,
          name: 'Work',
          color: '#0a1B2c',
        );
        expect(await applyTag(request), tagId);
        final tag = repository.snapshot.findPersonalTag(tagId)!;
        expect((tag.name, tag.color), ('Work', '#0a1B2c'));
        expect(skill().personalTagIds, [tagId]);
        await expectOneCommit(before, vocabularyChanged: true);

        final applied = repository.snapshot;
        final history = await operationHistory();
        expect(await applyTag(request), tagId);
        await expectNoCommit(applied, history);
        await driftFailure(
          repository.applyRemoteState(
            RemoteTagVocabulary.update(
              tagId: 'missing-tag',
              name: 'Work',
              color: null,
            ),
          ),
          SkillsErrorCode.personalTagNotFound,
        );
        expect(repository.snapshot, applied);
      },
    );

    test('merges assignments into the surviving tag in one commit', () async {
      final secondSource = await Directory(
        path.join(fixture.temporaryRoot.path, 'second'),
      ).create();
      await fixture.writeSkillMarkdown(secondSource.path, name: 'second-skill');
      final installed =
          await driftSuccess(
                repository.install(
                  InstallRequest(
                    source: LocalSourceDescriptor(locator: secondSource.path),
                    activationSelection: const ActivationSelection.none(),
                  ),
                ),
              )
              as InstallCompleted;
      final secondId = installed.report.affectedSkillIds.single;
      final mergeFrom = await localTag('Work');
      final survivingTag = await localTag('Business');
      await assign(skillId, mergeFrom);
      await assign(secondId, mergeFrom);
      await assign(secondId, survivingTag);

      final before = repository.snapshot.revision;
      expect(
        await applyTag(
          RemoteTagVocabulary.update(
            tagId: mergeFrom,
            name: ' BUSINESS ',
            color: '#fedcba',
          ),
        ),
        survivingTag,
      );
      final tag = repository.snapshot.personalTags.single;
      expect(
        (tag.id, tag.name, tag.color),
        (survivingTag, 'BUSINESS', '#fedcba'),
      );
      expect(skill().personalTagIds, [survivingTag]);
      expect(repository.snapshot.findSkill(secondId)!.personalTagIds, [
        survivingTag,
      ]);
      await expectOneCommit(
        before,
        metadata: {skillId, secondId},
        vocabularyChanged: true,
      );
    });

    test(
      'deletes assignments with the tag and repeats without another commit',
      () async {
        final tagId = await localTag('Work');
        final retained = await localTag('Home');
        await assign(skillId, tagId);
        await assign(skillId, retained);
        final request = RemoteTagVocabulary.delete(tagId: tagId);
        final before = repository.snapshot.revision;

        expect(await apply(request), isA<RemoteApplyRemoved>());
        expect(repository.snapshot.personalTags.single.id, retained);
        expect(skill().personalTagIds, [retained]);
        await expectOneCommit(
          before,
          metadata: {skillId},
          vocabularyChanged: true,
        );

        final applied = repository.snapshot;
        final history = await operationHistory();
        expect(await apply(request), isA<RemoteApplyNoChange>());
        await expectNoCommit(applied, history);
      },
    );
  });
}
