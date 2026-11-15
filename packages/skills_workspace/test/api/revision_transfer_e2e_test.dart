import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/infrastructure/database/operation_plan_codec.dart';
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import '../support/git_transport/git_http_backend_server.dart';

void main() {
  final originalWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalWarning,
  );
  late Directory root;
  late Directory source;
  late SkillsRepository a, b;
  late ManagedSkillId aId, bId;

  Future<T> success<T>(SkillsOperation<T> operation) async {
    final result = await operation.completed;
    expect(result, isA<SkillsSuccess<T>>(), reason: '$result');
    return result.valueOrNull as T;
  }

  Future<CommittedRevisionBatch> capture(
    SkillsRepository repo,
    ManagedSkillId id,
  ) => success(
    repo.exportCommittedRevision(
      ExportCommittedRevisionRequest(
        managedSkillId: id,
        expectedRevision: repo.snapshot.revision,
      ),
    ),
  );
  Future<void> publish(
    SkillsRepository repo,
    ManagedSkillId id,
    String value,
  ) async {
    final draft = await success(
      repo.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
    );
    await File(path.join(draft.path, 'notes.md')).writeAsString(value);
    await success(repo.publishDraft(PublishDraftRequest(managedSkillId: id)));
  }

  String workspace(String name) => path.join(root.path, name);
  SkillsRepository create(String name) => createSkillsRepository(
    SkillsRepositoryConfiguration(
      rootPath: workspace(name),
      agentHomePath: path.join(root.path, 'agent-home'),
      defaultLockWaitPolicy: LockWaitPolicy.wait(
        timeout: const Duration(seconds: 10),
      ),
    ),
  );

  Map<String, Object?> pointers(String name, ManagedSkillId id) {
    final database = sqlite3.open(
      path.join(workspace(name), 'workspace.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      return Map<String, Object?>.of(
        database.select(
          'SELECT source_lineage_id, upstream_object_id, effective_object_id FROM current_revision_selection WHERE managed_skill_id = ?',
          [id.value],
        ).single,
      );
    } finally {
      database.close();
    }
  }

  Future<IncomingRevisionApplyResult> apply(
    CommittedRevisionBatch incoming,
    CommittedRevisionReference expected,
  ) async {
    final local = await success(
      b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
    );
    return success(
      b.applyIncomingRevision(
        ApplyIncomingRevisionRequest(
          managedSkillId: bId,
          expectedRevision: b.snapshot.revision,
          expectedIdentity: local.identity,
          expectedEffective: expected,
          incoming: incoming,
        ),
      ),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('revision-transfer-e2e-');
    source = await Directory(path.join(root.path, 'source')).create();
    await File(path.join(source.path, 'SKILL.md')).writeAsString(
      '---\nname: transfer-fixture\ndescription: Transfer fixture\n---\n# Fixture\n',
    );
    await File(path.join(source.path, 'notes.md')).writeAsString('base\n');
    a = create('a');
    b = create('b');
    await success(a.open());
    await success(b.open());
    Future<ManagedSkillId> install(SkillsRepository repo) async {
      final result = await success(
        repo.install(
          InstallRequest(
            source: LocalSourceDescriptor(locator: source.path),
            activationSelection: const ActivationSelection.none(),
          ),
        ),
      );
      return (result as InstallCompleted).report.affectedSkillIds.single;
    }

    aId = await install(a);
    bId = await install(b);
  });
  tearDown(() async {
    if (a.isOpen) await a.close().completed;
    if (b.isOpen) await b.close().completed;
    if (Platform.isWindows) {
      await Process.run('attrib', [
        '-R',
        path.join(root.path, '*'),
        '/S',
        '/D',
      ]);
    } else {
      await Process.run('chmod', ['-R', 'u+w', root.path]);
    }
    await root.delete(recursive: true);
  });

  test(
    'conditional Removal checks live dirty Draft under writer and preserves selection',
    () async {
      final draft = await success(
        b.ensureDraft(EnsureDraftRequest(managedSkillId: bId)),
      );
      final before = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      final selection = pointers('b', bId);
      await File(
        path.join(draft.path, 'notes.md'),
      ).writeAsString('edited after reviewed capture');
      expect(b.snapshot.revision, before.snapshot.revision);
      final rejected = await b
          .remove(
            RemoveRequest(
              managedSkillIds: {bId},
              intent: DestructiveIntent(
                reviewedRevision: before.snapshot.revision,
              ),
              expectedIdentity: before.identity,
              expectedLocalLineageFingerprints: {
                bId: before.localLineageFingerprints[bId]!,
              },
              requireCleanDraft: true,
            ),
          )
          .completed;
      expect(
        rejected.failureOrNull?.code,
        SkillsErrorCode.dirtyDraftResolutionRequired,
      );
      expect(pointers('b', bId), selection);
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        'edited after reviewed capture',
      );
      expect(b.snapshot.revision, before.snapshot.revision);
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(
              reviewedRevision: before.snapshot.revision,
            ),
          ),
        ),
      );
      expect(b.snapshot.findSkill(bId), isNull);
    },
  );

  test(
    'conditional Removal accepts an unchanged clean Draft generation',
    () async {
      await success(b.ensureDraft(EnsureDraftRequest(managedSkillId: bId)));
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
            requireCleanDraft: true,
          ),
        ),
      );
      expect(b.snapshot.findSkill(bId), isNull);
    },
  );

  test(
    'equal roots import missing remote events and preserve both independent install histories',
    () async {
      final remote = await capture(a, aId), local = await capture(b, bId);
      expect(local.currentEffective, remote.currentEffective);
      final ownEvent = local.publishedHistory.single.eventFingerprint;
      final remoteEvent = remote.publishedHistory.single.eventFingerprint;
      expect(ownEvent, isNot(remoteEvent));
      final initialPointers = pointers('b', bId);
      final before = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      final prepared = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            managedSkillId: bId,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174801',
            ),
            expectedIdentity: before.identity,
            expectedRevision: before.snapshot.revision,
            contentManifest: remote.wireManifest,
            packBytes: remote.packBytes,
          ),
        ),
      );
      final applied = await success(
        b.applyIncomingRevision(
          ApplyIncomingRevisionRequest(
            managedSkillId: bId,
            expectedIdentity: before.identity,
            expectedRevision: before.snapshot.revision,
            expectedEffective: local.currentEffective,
            incoming: prepared,
          ),
        ),
      );
      expect(applied, isNot(isA<IncomingRevisionUnchanged>()));
      expect(pointers('b', bId), initialPointers);
      final union = await capture(b, bId);
      expect(
        union.publishedHistory.map((event) => event.eventFingerprint).toSet(),
        {ownEvent, remoteEvent},
      );
      final beforeNoop = b.snapshot.revision;
      final reservedNoop = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            managedSkillId: bId,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174802',
            ),
            expectedIdentity: before.identity,
            expectedRevision: beforeNoop,
            contentManifest: remote.wireManifest,
            packBytes: remote.packBytes,
          ),
        ),
      );
      final noop = await b
          .applyIncomingRevision(
            ApplyIncomingRevisionRequest(
              managedSkillId: bId,
              expectedIdentity: before.identity,
              expectedRevision: beforeNoop,
              expectedEffective: union.currentEffective,
              incoming: reservedNoop,
            ),
          )
          .completed;
      expect(noop.isSuccess, isTrue);
      expect((noop as SkillsSuccess).changed, isFalse);
      expect(b.snapshot.revision, beforeNoop);
      expect(
        (await success(
          b.inspectIncomingRevisionOutcome(
            InspectIncomingRevisionOutcomeRequest(
              binding: reservedNoop.localCommand!,
            ),
          ),
        )).status,
        IncomingRevisionOutcomeStatus.applied,
      );
      final conflictingManifest =
          jsonDecode(utf8.decode(remote.wireManifest)) as Map<String, Object?>;
      ((conflictingManifest['publishedHistory'] as List).single
              as Map)['kind'] =
          'adopt';
      final conflicting = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            managedSkillId: bId,
            expectedIdentity: before.identity,
            expectedRevision: b.snapshot.revision,
            contentManifest: utf8.encode(jsonEncode(conflictingManifest)),
            packBytes: remote.packBytes,
          ),
        ),
      );
      final rejected = await success(
        b.applyIncomingRevision(
          ApplyIncomingRevisionRequest(
            managedSkillId: bId,
            expectedIdentity: before.identity,
            expectedRevision: b.snapshot.revision,
            expectedEffective: union.currentEffective,
            incoming: conflicting,
          ),
        ),
      );
      expect(
        (rejected as IncomingRevisionPending).reason,
        IncomingRevisionPendingReason.invalidPayload,
      );
      await publish(b, bId, 'first publication after linking');
      final published = await capture(b, bId);
      expect(
        published.publishedHistory.map((event) => event.eventFingerprint),
        containsAll([ownEvent, remoteEvent]),
      );
      expect(published.publishedHistory, hasLength(3));
    },
  );

  test(
    'same-value Extra Data command completes its scoped receipt without a revision or later overwrite',
    () async {
      final assigned = await success(
        b.createPersonalTag(CreatePersonalTagRequest(name: 'already assigned')),
      );
      final removed = await success(
        b.createPersonalTag(CreatePersonalTagRequest(name: 'already absent')),
      );
      await success(
        b.assignPersonalTag(
          AssignPersonalTagRequest(managedSkillId: bId, tagId: assigned.id),
        ),
      );
      await success(
        b.setFavorite(
          SetFavoriteRequest(managedSkillId: bId, isFavorite: true),
        ),
      );
      await success(
        b.saveNote(SaveNoteRequest(managedSkillId: bId, text: 'same note')),
      );
      final authority = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      final patch = SkillExtraDataPatch(
        favorite: true,
        noteChanged: true,
        note: 'same note',
        addPersonalTagIds: {assigned.id},
        removePersonalTagIds: {removed.id},
      );
      final binding = await success(
        b.reserveSkillExtraDataPatch(
          ReserveSkillExtraDataPatchRequest(
            managedSkillId: bId,
            expectedIdentity: authority.identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174803',
            ),
            patch: patch,
          ),
        ),
      );
      final revision = b.snapshot.revision;
      final unreserved = IncomingRevisionCommandBinding(
        operationId: OperationId('123e4567-e89b-42d3-a456-426614174806'),
        requestFingerprint: binding.requestFingerprint,
        targetManagedSkillId: bId,
        localLineageFingerprint: binding.localLineageFingerprint,
        expectedIdentity: authority.identity,
      );
      final unknown = await success(
        b.applySkillExtraDataPatch(
          ApplySkillExtraDataPatchRequest(
            binding: unreserved,
            expectedRevision: revision,
            patch: patch,
          ),
        ),
      );
      expect(unknown, isA<IncomingRevisionPending>());
      expect(b.snapshot.revision, revision);
      final result = await b
          .applySkillExtraDataPatch(
            ApplySkillExtraDataPatchRequest(
              binding: binding,
              expectedRevision: revision,
              patch: patch,
            ),
          )
          .completed;
      expect(result.isSuccess, isTrue);
      expect((result as SkillsSuccess).changed, isFalse);
      expect(b.snapshot.revision, revision);
      var proof = await success(
        b.inspectIncomingRevisionOutcome(
          InspectIncomingRevisionOutcomeRequest(binding: binding),
        ),
      );
      expect(proof.status, IncomingRevisionOutcomeStatus.applied);
      expect(proof.committedRevision, revision);
      await success(b.close());
      b = create('b');
      await success(b.open());
      await success(
        b.saveNote(
          SaveNoteRequest(managedSkillId: bId, text: 'newer local note'),
        ),
      );
      final editedRevision = b.snapshot.revision;
      await success(
        b.applySkillExtraDataPatch(
          ApplySkillExtraDataPatchRequest(
            binding: binding,
            expectedRevision: revision,
            patch: patch,
          ),
        ),
      );
      expect(b.snapshot.findSkill(bId)!.note!.text, 'newer local note');
      expect(b.snapshot.revision, editedRevision);
      await success(b.deleteNote(DeleteNoteRequest(managedSkillId: bId)));
      final clearPatch = SkillExtraDataPatch(noteChanged: true, note: null);
      final clear = await success(
        b.reserveSkillExtraDataPatch(
          ReserveSkillExtraDataPatchRequest(
            managedSkillId: bId,
            expectedIdentity: authority.identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174804',
            ),
            patch: clearPatch,
          ),
        ),
      );
      final clearRevision = b.snapshot.revision;
      await success(
        b.applySkillExtraDataPatch(
          ApplySkillExtraDataPatchRequest(
            binding: clear,
            expectedRevision: clearRevision,
            patch: clearPatch,
          ),
        ),
      );
      expect(b.snapshot.revision, clearRevision);
      final raw = sqlite3.open(
        path.join(workspace('b'), 'workspace.sqlite'),
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          raw.select(
            'SELECT * FROM operation_records WHERE operation_id IN (?, ?)',
            [binding.operationId.value, clear.operationId.value],
          ),
          isEmpty,
        );
      } finally {
        raw.close();
      }
    },
  );

  test(
    'same-value Personal Tag command has exact durable receipt without a revision or later rename overwrite',
    () async {
      final tag = await success(
        b.createPersonalTag(CreatePersonalTagRequest(name: 'same tag')),
      );
      final authority = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      final mutation = PersonalTagMutation(
        kind: PersonalTagMutationKind.update,
        personalTagId: tag.id,
        name: tag.name,
        color: tag.color,
      );
      final binding = await success(
        b.reservePersonalTagMutation(
          ReservePersonalTagMutationRequest(
            expectedIdentity: authority.identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174805',
            ),
            mutation: mutation,
          ),
        ),
      );
      final revision = b.snapshot.revision;
      final unknown = await success(
        b.applyPersonalTagMutation(
          ApplyPersonalTagMutationRequest(
            binding: PersonalTagCommandBinding(
              operationId: OperationId('123e4567-e89b-42d3-a456-426614174807'),
              requestFingerprint: binding.requestFingerprint,
              personalTagId: binding.personalTagId,
              expectedIdentity: authority.identity,
            ),
            expectedRevision: revision,
            mutation: mutation,
          ),
        ),
      );
      expect(unknown.status, PersonalTagMutationStatus.unknown);
      expect(b.snapshot.revision, revision);
      final result = await b
          .applyPersonalTagMutation(
            ApplyPersonalTagMutationRequest(
              binding: binding,
              expectedRevision: revision,
              mutation: mutation,
            ),
          )
          .completed;
      expect(result.isSuccess, isTrue);
      expect((result as SkillsSuccess).changed, isFalse);
      expect(b.snapshot.revision, revision);
      expect(
        (await success(
          b.inspectPersonalTagMutationOutcome(
            InspectPersonalTagMutationOutcomeRequest(binding: binding),
          ),
        )).status,
        PersonalTagMutationStatus.applied,
      );
      await success(
        b.updatePersonalTag(
          UpdatePersonalTagRequest(tagId: tag.id, name: 'later rename'),
        ),
      );
      final later = b.snapshot.revision;
      await success(b.close());
      b = create('b');
      await success(b.open());
      await success(
        b.applyPersonalTagMutation(
          ApplyPersonalTagMutationRequest(
            binding: binding,
            expectedRevision: revision,
            mutation: mutation,
          ),
        ),
      );
      expect(b.snapshot.findPersonalTag(tag.id)!.name, 'later rename');
      expect(b.snapshot.revision, later);
    },
  );

  test(
    'early network staging failure cleans its registry and permits recovery or owner retirement',
    () async {
      Future<File> blockAndAttempt() async {
        final batch = await capture(b, bId);
        final blocker = File(
          path.join(
            workspace('b'),
            'revision-stores',
            '${bId.value}.git',
            'network-transfers',
          ),
        );
        await blocker.writeAsString('disposable blocker');
        final attempt = await b
            .pushCommittedRevision(
              PushCommittedRevisionRequest(
                managedSkillId: bId,
                expectedIdentity: batch.identity,
                expectedRevision: b.snapshot.revision,
                batch: batch,
                remote: RevisionTransferRemote.loopbackForTesting(
                  url: 'http://127.0.0.1:1/unused.git',
                  ephemeralHeaders: () async => [],
                ),
              ),
            )
            .completed;
        expect(attempt.isSuccess, isFalse);
        final incomplete = await success(
          b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
        );
        expect(incomplete.isComplete, isTrue);
        final db = sqlite3.open(path.join(workspace('b'), 'workspace.sqlite'));
        try {
          expect(
            db
                .select('SELECT COUNT(*) AS n FROM workspace_network_transfers')
                .single['n'],
            0,
          );
        } finally {
          db.close();
        }
        return blocker;
      }

      final blocker = await blockAndAttempt();
      await blocker.delete();
      await success(b.resumeFinalizationRecovery());
      expect(
        (await success(
          b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
        )).isComplete,
        isTrue,
      );
      await blockAndAttempt();
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
          ),
        ),
      );
      final retired = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(retired.snapshot.managedSkills, isEmpty);
      expect(retired.isComplete, isTrue);
      final db = sqlite3.open(path.join(workspace('b'), 'workspace.sqlite'));
      try {
        expect(
          db
              .select('SELECT COUNT(*) AS n FROM workspace_network_transfers')
              .single['n'],
          0,
        );
      } finally {
        db.close();
      }
    },
  );

  test(
    'Removal cancels and drains an active mapped Git fetch without remote acknowledgement',
    () async {
      final batch = await capture(b, bId);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<void>();
      final subscription = server.listen((request) {
        if (!seen.isCompleted) seen.complete();
        // Deliberately leave discovery unanswered until local cancellation.
      });
      addTearDown(subscription.cancel);
      final fetch = b.fetchIncomingRevision(
        FetchIncomingRevisionRequest(
          managedSkillId: bId,
          expectedIdentity: batch.identity,
          expectedRevision: b.snapshot.revision,
          contentManifest: batch.wireManifest,
          remote: RevisionTransferRemote.loopbackForTesting(
            url: 'http://127.0.0.1:${server.port}/stalled.git',
            ephemeralHeaders: () async => [],
          ),
        ),
      );
      await seen.future.timeout(const Duration(seconds: 10));
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
          ),
        ),
      );
      expect(
        (await fetch.completed).failureOrNull?.code,
        SkillsErrorCode.operationCancelled,
      );
      final retired = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(retired.isComplete, isTrue);
      expect(retired.snapshot.managedSkills, isEmpty);
    },
  );

  test(
    'public native push and bounded Git download install a real second Workspace without source reacquisition',
    () async {
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
          ),
        ),
      );
      await publish(a, aId, 'cloud transfer bytes\n');
      final batch = await capture(a, aId);
      final remotePath = path.join(root.path, 'remote.git');
      expect(
        (await Process.run('git', ['init', '--bare', remotePath])).exitCode,
        0,
      );
      expect(
        (await Process.run('git', [
          'config',
          'http.receivepack',
          'true',
        ], workingDirectory: remotePath)).exitCode,
        0,
      );
      final server = await GitHttpBackendServer.start(
        projectRoot: root.path,
        bearerToken: 'fixture-ephemeral-secret',
      );
      addTearDown(server.close);
      final remote = RevisionTransferRemote.loopbackForTesting(
        url: server.locatorFor('remote.git'),
        ephemeralHeaders: () async => [
          'Authorization: Bearer fixture-ephemeral-secret',
        ],
      );
      final aCapture = await success(
        a.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      final uploaded = await success(
        a.pushCommittedRevision(
          PushCommittedRevisionRequest(
            managedSkillId: aId,
            expectedIdentity: aCapture.identity,
            expectedRevision: a.snapshot.revision,
            batch: batch,
            remote: remote,
          ),
        ),
      );
      expect(uploaded.refs, everyElement(RevisionTransferRefStatus.accepted));
      // The selected Source is now unavailable. Incoming install must consume the
      // mirrored objects and logical provenance, not invoke install(Source).
      await source.rename(path.join(root.path, 'source-offline'));
      final bCapture = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      final incoming = await success(
        b.fetchIncomingRevision(
          FetchIncomingRevisionRequest(
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174177',
            ),
            expectedIdentity: bCapture.identity,
            expectedRevision: b.snapshot.revision,
            contentManifest: batch.wireManifest,
            remote: remote,
          ),
        ),
      );
      final binding = incoming.localCommand!;
      expect(binding.targetManagedSkillId, isNot(aId));
      final notStarted = await success(
        b.inspectIncomingRevisionOutcome(
          InspectIncomingRevisionOutcomeRequest(binding: binding),
        ),
      );
      expect(
        notStarted.status,
        IncomingRevisionOutcomeStatus.confirmedNotStarted,
      );
      expect(notStarted.capture!.isComplete, isTrue);
      await success(b.close());
      b = create('b');
      await success(b.open());
      final reservedAgain = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            localOperationId: binding.operationId,
            expectedIdentity: bCapture.identity,
            expectedRevision: b.snapshot.revision,
            contentManifest: incoming.wireManifest,
            packBytes: incoming.packBytes,
          ),
        ),
      );
      expect(
        reservedAgain.localCommand!.targetManagedSkillId,
        binding.targetManagedSkillId,
      );
      expect(
        reservedAgain.localCommand!.requestFingerprint,
        binding.requestFingerprint,
      );
      final result = await success(
        b.installIncomingRevision(
          InstallIncomingRevisionRequest(
            expectedIdentity: bCapture.identity,
            expectedRevision: b.snapshot.revision,
            incoming: incoming,
          ),
        ),
      );
      final proof = await success(
        b.inspectIncomingRevisionOutcome(
          InspectIncomingRevisionOutcomeRequest(binding: binding),
        ),
      );
      expect(proof.status, IncomingRevisionOutcomeStatus.applied);
      final appliedRevision = b.snapshot.revision;
      await success(b.close());
      b = create('b');
      await success(b.open());
      final replayed = await success(
        b.installIncomingRevision(
          InstallIncomingRevisionRequest(
            expectedIdentity: bCapture.identity,
            expectedRevision: bCapture.snapshot.revision,
            incoming: incoming,
          ),
        ),
      );
      expect(replayed, isA<IncomingRevisionReplayed>());
      expect(b.snapshot.revision, appliedRevision);
      final installed = result as IncomingRevisionInstalled;
      bId = installed.managedSkillId;
      final selected = pointers('b', bId), original = pointers('a', aId);
      expect(selected['effective_object_id'], original['effective_object_id']);
      expect(selected['upstream_object_id'], original['upstream_object_id']);
      expect(b.snapshot.findSkill(bId)!.source, batch.source);
      expect(b.snapshot.findSkill(bId)!.activations, isEmpty);
      final history = await success(
        b.inspectPublishedHistory(PublishedHistoryRequest(managedSkillId: bId)),
      );
      expect(history.revisions, hasLength(batch.publishedHistory.length));
      expect(
        history.revisions.every(
          (entry) => entry.origin == PublishedRevisionOrigin.imported,
        ),
        isTrue,
      );
      final exported = await capture(b, bId);
      expect(exported.currentEffective, batch.currentEffective);
      expect(
        exported.publishedHistory
            .map((entry) => entry.eventFingerprint)
            .toSet(),
        batch.publishedHistory.map((entry) => entry.eventFingerprint).toSet(),
      );

      final duplicate = await success(
        b.installIncomingRevision(
          InstallIncomingRevisionRequest(
            expectedIdentity: bCapture.identity,
            expectedRevision: b.snapshot.revision,
            incoming: incoming,
          ),
        ),
      );
      expect(duplicate, isA<IncomingRevisionReplayed>());
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
          ),
        ),
      );
      final absentProof = await success(
        b.inspectIncomingRevisionOutcome(
          InspectIncomingRevisionOutcomeRequest(binding: binding),
        ),
      );
      expect(absentProof.status, IncomingRevisionOutcomeStatus.targetAbsent);
      final raw = sqlite3.open(
        path.join(workspace('b'), 'workspace.sqlite'),
        mode: OpenMode.readOnly,
      );
      expect(raw.select('SELECT * FROM workspace_incoming_outcomes'), isEmpty);
      expect(
        raw.select('SELECT * FROM workspace_incoming_reservations'),
        isEmpty,
      );
      expect(
        raw.select('SELECT * FROM operation_records WHERE operation_id = ?', [
          binding.operationId.value,
        ]),
        isEmpty,
      );
      raw.close();
    },
  );

  for (final failAfterCommit in [false, true]) {
    test(
      'incoming replacement preserves Managed Skill metadata, retires old history and ${failAfterCommit ? 'recovers committed finalization' : 'replays exact outcome'}',
      () async {
        final before = await capture(b, bId);
        final authority = await success(
          b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
        );
        final oldLineage = authority.localLineageFingerprints[bId]!;
        await success(
          b.setFavorite(
            SetFavoriteRequest(managedSkillId: bId, isFavorite: true),
          ),
        );
        await success(
          b.saveNote(
            SaveNoteRequest(managedSkillId: bId, text: 'keep metadata'),
          ),
        );
        final nextSource = await Directory(
          path.join(root.path, 'new-source'),
        ).create();
        await File(path.join(nextSource.path, 'SKILL.md')).writeAsString(
          '---\nname: replacement-fixture\ndescription: Replacement\n---\n# New lineage\n',
        );
        await success(
          a.replaceSource(
            ReplaceSourceRequest(
              managedSkillId: aId,
              source: LocalSourceDescriptor(locator: nextSource.path),
              intent: DestructiveIntent(reviewedRevision: a.snapshot.revision),
            ),
          ),
        );
        await publish(a, aId, 'new lineage customized\n');
        final batch = await capture(a, aId);
        final prepared = await success(
          b.prepareIncomingRevision(
            PrepareIncomingRevisionRequest(
              managedSkillId: bId,
              localOperationId: OperationId(
                failAfterCommit
                    ? '123e4567-e89b-42d3-a456-426614174189'
                    : '123e4567-e89b-42d3-a456-426614174188',
              ),
              replaceExistingLineage: true,
              expectedIdentity: before.identity,
              expectedRevision: b.snapshot.revision,
              contentManifest: batch.wireManifest,
              packBytes: batch.packBytes,
            ),
          ),
        );
        final binding = prepared.localCommand!;
        expect(binding.previousLocalLineageFingerprint, oldLineage);
        expect(binding.previousEffectiveReference, before.currentEffective);
        final draft = await success(
          b.ensureDraft(EnsureDraftRequest(managedSkillId: bId)),
        );
        await File(
          path.join(draft.path, 'notes.md'),
        ).writeAsString('dirty local content\n');
        ReplaceIncomingRevisionRequest request() =>
            ReplaceIncomingRevisionRequest(
              managedSkillId: bId,
              expectedIdentity: before.identity,
              expectedRevision: b.snapshot.revision,
              expectedLocalLineageFingerprint: oldLineage,
              expectedEffective: before.currentEffective,
              incoming: prepared,
            );
        final dirty = await success(b.replaceIncomingRevision(request()));
        expect(
          (dirty as IncomingRevisionPending).reason,
          IncomingRevisionPendingReason.dirtyDraft,
        );
        expect(
          (await capture(b, bId)).currentEffective,
          before.currentEffective,
        );
        await success(b.discardDraft(DiscardDraftRequest(managedSkillId: bId)));
        if (failAfterCommit) {
          await File(
            path.join(workspace('b'), 'control-plane-backups', '1'),
          ).writeAsString('blocks post-commit epoch');
        }
        final result = await b.replaceIncomingRevision(request()).completed;
        if (failAfterCommit) {
          expect(
            result,
            isA<
              SkillsCommittedFinalizationPending<IncomingRevisionApplyResult>
            >(),
          );
          await File(
            path.join(workspace('b'), 'control-plane-backups', '1'),
          ).delete();
          await success(b.resumeFinalizationRecovery());
        } else {
          expect(result, isA<SkillsSuccess<IncomingRevisionApplyResult>>());
        }
        final selected = pointers('b', bId), remote = pointers('a', aId);
        expect(selected['effective_object_id'], remote['effective_object_id']);
        expect(selected['upstream_object_id'], remote['upstream_object_id']);
        expect(b.snapshot.findSkill(bId)!.source, batch.source);
        expect(b.snapshot.findSkill(bId)!.favorite.isFavorite, isTrue);
        expect(b.snapshot.findSkill(bId)!.note!.text, 'keep metadata');
        final current = await success(
          b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
        );
        expect(current.localLineageFingerprints[bId], isNot(oldLineage));
        final revision = current.snapshot.revision;
        await success(b.close());
        b = create('b');
        await success(b.open());
        expect(
          (await success(
            b.inspectIncomingRevisionOutcome(
              InspectIncomingRevisionOutcomeRequest(binding: binding),
            ),
          )).status,
          IncomingRevisionOutcomeStatus.applied,
        );
        expect(
          await success(b.replaceIncomingRevision(request())),
          isA<IncomingRevisionReplayed>(),
        );
        expect(b.snapshot.revision, revision);
        final oldRemove = await b
            .remove(
              RemoveRequest(
                managedSkillIds: {bId},
                intent: DestructiveIntent(reviewedRevision: revision),
                expectedIdentity: before.identity,
                expectedLocalLineageFingerprints: {bId: oldLineage},
              ),
            )
            .completed;
        expect(oldRemove.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
        expect(b.snapshot.findSkill(bId), isNotNull);
        final exported = await capture(b, bId);
        expect(
          exported.publishedHistory
              .map((entry) => entry.eventFingerprint)
              .toSet(),
          batch.publishedHistory.map((entry) => entry.eventFingerprint).toSet(),
        );
        final db = sqlite3.open(
          path.join(workspace('b'), 'workspace.sqlite'),
          mode: OpenMode.readOnly,
        );
        expect(db.select('SELECT * FROM source_lineages').length, 1);
        expect(
          db.select(
            'SELECT expected_effective_object_id FROM workspace_incoming_outcomes WHERE operation_id = ?',
            [binding.operationId.value],
          ).single['expected_effective_object_id'],
          isNull,
        );
        db.close();
        expect(
          await Directory(
            path.join(workspace('b'), 'control-plane-backups', '0'),
          ).exists(),
          isFalse,
        );
        for (final file in Directory(
          path.join(workspace('b'), 'control-plane-backups'),
        ).listSync(recursive: true).whereType<File>()) {
          final text = latin1.decode(await file.readAsBytes());
          expect(text, isNot(contains(source.path)));
          expect(
            text,
            isNot(contains(pointers('a', aId)['source_lineage_id']! as String)),
          );
        }
      },
    );
  }

  test(
    'caller-bound global Personal Tags create, rename and delete with independent exact receipts',
    () async {
      final identity = (await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      )).identity;
      final mutation = PersonalTagMutation(
        kind: PersonalTagMutationKind.create,
        name: 'Cloud tag',
        color: '#112233',
      );
      final binding = await success(
        b.reservePersonalTagMutation(
          ReservePersonalTagMutationRequest(
            expectedIdentity: identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174184',
            ),
            mutation: mutation,
          ),
        ),
      );
      expect(
        (await success(
          b.inspectPersonalTagMutationOutcome(
            InspectPersonalTagMutationOutcomeRequest(binding: binding),
          ),
        )).status,
        PersonalTagMutationStatus.confirmedNotStarted,
      );
      final created = await success(
        b.applyPersonalTagMutation(
          ApplyPersonalTagMutationRequest(
            binding: binding,
            expectedRevision: b.snapshot.revision,
            mutation: mutation,
          ),
        ),
      );
      expect(created.status, PersonalTagMutationStatus.applied);
      expect(
        b.snapshot.findPersonalTag(binding.personalTagId)!.name,
        'Cloud tag',
      );
      await success(
        b.updatePersonalTag(
          UpdatePersonalTagRequest(
            tagId: binding.personalTagId,
            name: 'User rename',
            color: '#445566',
          ),
        ),
      );
      final revision = b.snapshot.revision;
      await success(b.close());
      b = create('b');
      await success(b.open());
      expect(
        (await success(
          b.inspectPersonalTagMutationOutcome(
            InspectPersonalTagMutationOutcomeRequest(binding: binding),
          ),
        )).status,
        PersonalTagMutationStatus.applied,
      );
      expect(
        (await success(
          b.applyPersonalTagMutation(
            ApplyPersonalTagMutationRequest(
              binding: binding,
              expectedRevision: RepositoryRevision(0),
              mutation: mutation,
            ),
          ),
        )).status,
        PersonalTagMutationStatus.applied,
      );
      expect(b.snapshot.revision, revision);
      expect(
        b.snapshot.findPersonalTag(binding.personalTagId)!.name,
        'User rename',
      );
      final collision = PersonalTagMutation(
        kind: PersonalTagMutationKind.create,
        name: 'USER RENAME',
      );
      final collisionBinding = await success(
        b.reservePersonalTagMutation(
          ReservePersonalTagMutationRequest(
            expectedIdentity: identity,
            expectedRevision: revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174185',
            ),
            mutation: collision,
          ),
        ),
      );
      final pending = await success(
        b.applyPersonalTagMutation(
          ApplyPersonalTagMutationRequest(
            binding: collisionBinding,
            expectedRevision: revision,
            mutation: collision,
          ),
        ),
      );
      expect(pending.status, PersonalTagMutationStatus.nameConflict);
      expect(b.snapshot.revision, revision);
      expect(b.snapshot.personalTags, hasLength(1));
      final update = PersonalTagMutation(
        kind: PersonalTagMutationKind.update,
        personalTagId: binding.personalTagId,
        name: 'Remote rename',
      );
      final updateBinding = await success(
        b.reservePersonalTagMutation(
          ReservePersonalTagMutationRequest(
            expectedIdentity: identity,
            expectedRevision: revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174186',
            ),
            mutation: update,
          ),
        ),
      );
      await success(
        b.applyPersonalTagMutation(
          ApplyPersonalTagMutationRequest(
            binding: updateBinding,
            expectedRevision: revision,
            mutation: update,
          ),
        ),
      );
      final remove = PersonalTagMutation(
        kind: PersonalTagMutationKind.delete,
        personalTagId: binding.personalTagId,
      );
      final removeBinding = await success(
        b.reservePersonalTagMutation(
          ReservePersonalTagMutationRequest(
            expectedIdentity: identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174187',
            ),
            mutation: remove,
          ),
        ),
      );
      await success(
        b.applyPersonalTagMutation(
          ApplyPersonalTagMutationRequest(
            binding: removeBinding,
            expectedRevision: b.snapshot.revision,
            mutation: remove,
          ),
        ),
      );
      expect(b.snapshot.findPersonalTag(binding.personalTagId), isNull);
      expect(
        (await success(
          b.inspectPersonalTagMutationOutcome(
            InspectPersonalTagMutationOutcomeRequest(binding: removeBinding),
          ),
        )).status,
        PersonalTagMutationStatus.applied,
      );
    },
  );

  test(
    'source rename keeps historical names and exact ancestry when mirrored into an empty Workspace',
    () async {
      final originalHistory = await success(
        a.inspectPublishedHistory(PublishedHistoryRequest(managedSkillId: aId)),
      );
      await File(path.join(source.path, 'SKILL.md')).writeAsString(
        '---\nname: renamed-transfer\ndescription: Renamed source\n---\n# Renamed\n',
      );
      await success(a.update(UpdateRequest(managedSkillIds: {aId})));
      expect(a.snapshot.findSkill(aId)!.slotKey, 'renamed-transfer');
      final batch = await capture(a, aId);
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
          ),
        ),
      );
      final identity = (await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      )).identity;
      final received = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            expectedIdentity: identity,
            expectedRevision: b.snapshot.revision,
            contentManifest: batch.wireManifest,
            packBytes: batch.packBytes,
          ),
        ),
      );
      final installed =
          await success(
                b.installIncomingRevision(
                  InstallIncomingRevisionRequest(
                    expectedIdentity: identity,
                    expectedRevision: b.snapshot.revision,
                    incoming: received,
                  ),
                ),
              )
              as IncomingRevisionInstalled;
      bId = installed.managedSkillId;
      expect(b.snapshot.findSkill(bId)!.slotKey, 'renamed-transfer');
      final history = await success(
        b.inspectPublishedHistory(PublishedHistoryRequest(managedSkillId: bId)),
      );
      expect(history.revisions.length, batch.publishedHistory.length);
      final old = history.revisions.firstWhere(
        (entry) =>
            entry.contentHash == originalHistory.revisions.single.contentHash,
      );
      final refused = await b
          .restorePublish(
            RestorePublishRequest(
              managedSkillId: bId,
              selectedRevision: old.reference,
            ),
          )
          .completed;
      expect(
        refused.failureOrNull?.code,
        SkillsErrorCode.historicalNameMismatch,
      );
      final exported = await capture(b, bId);
      expect(
        exported.publishedHistory
            .map((entry) => entry.eventFingerprint)
            .toSet(),
        batch.publishedHistory.map((entry) => entry.eventFingerprint).toSet(),
      );
    },
  );

  test(
    'one caller-bound Extra Data patch is atomic and ack-loss replay preserves a newer local Note',
    () async {
      final identity = (await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      )).identity;
      final tag = await success(
        b.createPersonalTag(CreatePersonalTagRequest(name: 'Synced local tag')),
      );
      final patch = SkillExtraDataPatch(
        favorite: true,
        noteChanged: true,
        note: 'remote Note',
        addPersonalTagIds: {tag.id},
      );
      final binding = await success(
        b.reserveSkillExtraDataPatch(
          ReserveSkillExtraDataPatchRequest(
            managedSkillId: bId,
            expectedIdentity: identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174180',
            ),
            patch: patch,
          ),
        ),
      );
      expect(
        (await success(
          b.inspectIncomingRevisionOutcome(
            InspectIncomingRevisionOutcomeRequest(binding: binding),
          ),
        )).status,
        IncomingRevisionOutcomeStatus.confirmedNotStarted,
      );
      expect(
        await success(
          b.applySkillExtraDataPatch(
            ApplySkillExtraDataPatchRequest(
              binding: binding,
              expectedRevision: b.snapshot.revision,
              patch: patch,
            ),
          ),
        ),
        isA<IncomingRevisionApplied>(),
      );
      final skill = b.snapshot.findSkill(bId)!;
      expect(skill.favorite.isFavorite, isTrue);
      expect(skill.note!.text, 'remote Note');
      expect(skill.personalTagIds, contains(tag.id));
      await success(
        b.saveNote(SaveNoteRequest(managedSkillId: bId, text: 'new user Note')),
      );
      final revision = b.snapshot.revision;
      await success(b.close());
      b = create('b');
      await success(b.open());
      expect(
        (await success(
          b.inspectIncomingRevisionOutcome(
            InspectIncomingRevisionOutcomeRequest(binding: binding),
          ),
        )).status,
        IncomingRevisionOutcomeStatus.applied,
      );
      expect(
        await success(
          b.applySkillExtraDataPatch(
            ApplySkillExtraDataPatchRequest(
              binding: binding,
              expectedRevision: RepositoryRevision(0),
              patch: patch,
            ),
          ),
        ),
        isA<IncomingRevisionReplayed>(),
      );
      expect(b.snapshot.revision, revision);
      expect(b.snapshot.findSkill(bId)!.note!.text, 'new user Note');
      final wrong = await b
          .applySkillExtraDataPatch(
            ApplySkillExtraDataPatchRequest(
              binding: binding,
              expectedRevision: revision,
              patch: SkillExtraDataPatch(
                noteChanged: true,
                note: 'different request',
              ),
            ),
          )
          .completed;
      expect(wrong, isA<SkillsFailure<IncomingRevisionApplyResult>>());
      final clear = SkillExtraDataPatch(
        favorite: false,
        noteChanged: true,
        removePersonalTagIds: {tag.id},
      );
      final clearBinding = await success(
        b.reserveSkillExtraDataPatch(
          ReserveSkillExtraDataPatchRequest(
            managedSkillId: bId,
            expectedIdentity: identity,
            expectedRevision: revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174181',
            ),
            patch: clear,
          ),
        ),
      );
      await success(
        b.applySkillExtraDataPatch(
          ApplySkillExtraDataPatchRequest(
            binding: clearBinding,
            expectedRevision: revision,
            patch: clear,
          ),
        ),
      );
      expect(b.snapshot.findSkill(bId)!.favorite.isFavorite, isFalse);
      expect(b.snapshot.findSkill(bId)!.note, isNull);
      expect(
        b.snapshot.findSkill(bId)!.personalTagIds,
        isNot(contains(tag.id)),
      );
      final badTag = await success(
        b.reserveSkillExtraDataPatch(
          ReserveSkillExtraDataPatchRequest(
            managedSkillId: bId,
            expectedIdentity: identity,
            expectedRevision: b.snapshot.revision,
            localOperationId: OperationId(
              '123e4567-e89b-42d3-a456-426614174182',
            ),
            patch: SkillExtraDataPatch(
              favorite: true,
              addPersonalTagIds: {'missing-local-tag'},
            ),
          ),
        ),
      );
      final before = b.snapshot.revision;
      final failed = await b
          .applySkillExtraDataPatch(
            ApplySkillExtraDataPatchRequest(
              binding: badTag,
              expectedRevision: before,
              patch: SkillExtraDataPatch(
                favorite: true,
                addPersonalTagIds: {'missing-local-tag'},
              ),
            ),
          )
          .completed;
      expect(failed, isA<SkillsFailure<IncomingRevisionApplyResult>>());
      expect(b.snapshot.revision, before);
      expect(b.snapshot.findSkill(bId)!.favorite.isFavorite, isFalse);
    },
  );

  test(
    'caller-bound fast-forward proves an earlier apply after later local edits and rejects different payloads',
    () async {
      final baseline = await capture(b, bId);
      await publish(a, aId, 'remote first\n');
      final incoming = await capture(a, aId);
      final operation = OperationId('123e4567-e89b-42d3-a456-426614174178');
      final prepared = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            managedSkillId: bId,
            localOperationId: operation,
            expectedIdentity: baseline.identity,
            expectedRevision: b.snapshot.revision,
            contentManifest: incoming.wireManifest,
            packBytes: incoming.packBytes,
          ),
        ),
      );
      final binding = prepared.localCommand!;
      expect(
        (await success(
          b.inspectIncomingRevisionOutcome(
            InspectIncomingRevisionOutcomeRequest(binding: binding),
          ),
        )).status,
        IncomingRevisionOutcomeStatus.confirmedNotStarted,
      );
      final first = b.applyIncomingRevision(
        ApplyIncomingRevisionRequest(
          managedSkillId: bId,
          expectedIdentity: baseline.identity,
          expectedRevision: b.snapshot.revision,
          expectedEffective: baseline.currentEffective,
          incoming: prepared,
        ),
      );
      final concurrent = b.applyIncomingRevision(
        ApplyIncomingRevisionRequest(
          managedSkillId: bId,
          expectedIdentity: baseline.identity,
          expectedRevision: b.snapshot.revision,
          expectedEffective: baseline.currentEffective,
          incoming: prepared,
        ),
      );
      expect(
        (await concurrent.completed).failureOrNull?.code,
        SkillsErrorCode.repositoryBusy,
      );
      expect(await success(first), isA<IncomingRevisionApplied>());
      await publish(b, bId, 'new local edit after remote apply\n');
      final selected = pointers('b', bId), revision = b.snapshot.revision;
      final proof = await success(
        b.inspectIncomingRevisionOutcome(
          InspectIncomingRevisionOutcomeRequest(binding: binding),
        ),
      );
      expect(proof.status, IncomingRevisionOutcomeStatus.applied);
      final replay = await success(
        b.applyIncomingRevision(
          ApplyIncomingRevisionRequest(
            managedSkillId: bId,
            expectedIdentity: baseline.identity,
            expectedRevision: baseline.identity == prepared.identity
                ? RepositoryRevision(0)
                : revision,
            expectedEffective: baseline.currentEffective,
            incoming: prepared,
          ),
        ),
      );
      expect(replay, isA<IncomingRevisionReplayed>());
      expect(pointers('b', bId), selected);
      expect(b.snapshot.revision, revision);
      await publish(a, aId, 'remote second different request\n');
      final changed = await capture(a, aId);
      final conflict = await b
          .prepareIncomingRevision(
            PrepareIncomingRevisionRequest(
              managedSkillId: bId,
              localOperationId: operation,
              expectedIdentity: baseline.identity,
              expectedRevision: b.snapshot.revision,
              contentManifest: changed.wireManifest,
              packBytes: changed.packBytes,
            ),
          )
          .completed;
      expect(conflict, isA<SkillsFailure<CommittedRevisionBatch>>());
      final unknown = IncomingRevisionCommandBinding(
        operationId: OperationId('123e4567-e89b-42d3-a456-426614174179'),
        requestFingerprint: binding.requestFingerprint,
        targetManagedSkillId: bId,
        localLineageFingerprint: binding.localLineageFingerprint,
        expectedIdentity: baseline.identity,
      );
      expect(
        (await success(
          b.inspectIncomingRevisionOutcome(
            InspectIncomingRevisionOutcomeRequest(binding: unknown),
          ),
        )).status,
        IncomingRevisionOutcomeStatus.unknown,
      );
    },
  );

  test(
    'authoritative capture refuses a pending v4 Journal and recovers without changing incarnation',
    () async {
      final before = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(before.isComplete, isTrue);
      final operationId = OperationId('123e4567-e89b-42d3-a456-426614174133');
      final next = before.snapshot.revision.next();
      final envelope = PreparedOperationEnvelope(
        operationId: operationId,
        expectedRepositoryRevision: before.snapshot.revision,
        committedRepositoryRevision: next,
        operationGeneration: next.value,
        preparationSteps: [
          PreparationOperationStep(
            stepId: 'legacy.prepare',
            kind: PreparationStepKind.revisionCandidate,
            recoveryReference: RecoveryReference(
              'or1:${operationId.value}:candidate-${bId.value}',
            ),
          ),
        ],
        record: OperationRecordPlan(
          operationId: operationId,
          kind: 'update',
          subjects: [],
          retainWithoutSubjects: true,
        ),
      );
      final database = sqlite3.open(
        path.join(workspace('b'), 'workspace.sqlite'),
      );
      try {
        database.execute(
          'INSERT INTO operation_journals VALUES (?, ?, ?, 4, ?, ?, NULL, 1, 2)',
          [
            operationId.value,
            'update',
            'prepared',
            const OperationPlanCodec().encodeDefinition(envelope),
            next.value,
          ],
        );
        database.execute(
          'INSERT INTO operation_journal_steps VALUES (?, 0, ?, ?, ?, ?)',
          [
            operationId.value,
            'legacy.prepare',
            'revisionCandidate',
            'planned',
            'or1:${operationId.value}:candidate-${bId.value}',
          ],
        );
      } finally {
        database.close();
      }
      final pending = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(pending.snapshot.revision, before.snapshot.revision);
      expect(pending.recoveryComplete, isFalse);
      expect(pending.finalizationComplete, isFalse);
      expect(pending.isComplete, isFalse);
      await success(b.close());
      b = create('b');
      await success(b.open());
      final recovered = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(recovered.identity, before.identity);
      expect(recovered.snapshot.revision, before.snapshot.revision);
      expect(recovered.isComplete, isTrue);
    },
  );

  test(
    'real primary recovery changes incarnation and rejects a previously bound apply',
    () async {
      final before = await capture(b, bId);
      final captureBefore = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(captureBefore.isComplete, isTrue);
      await publish(a, aId, 'incoming after recovery\n');
      final incoming = await capture(a, aId);
      await success(b.close());
      b = create('b');
      await success(b.open());
      expect(
        (await success(
          b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
        )).identity,
        before.identity,
      );
      await success(b.close());
      await File(
        path.join(workspace('b'), 'workspace.sqlite'),
      ).writeAsBytes([0, 1, 2, 3]);
      b = create('b');
      await success(b.open());
      final restored = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(restored.identity.workspaceId, before.identity.workspaceId);
      expect(
        restored.identity.recoveryIncarnation,
        isNot(before.identity.recoveryIncarnation),
      );
      expect(restored.isComplete, isTrue);
      final result = await success(
        b.applyIncomingRevision(
          ApplyIncomingRevisionRequest(
            managedSkillId: bId,
            expectedRevision: b.snapshot.revision,
            expectedIdentity: before.identity,
            expectedEffective: before.currentEffective,
            incoming: incoming,
          ),
        ),
      );
      expect(
        (result as IncomingRevisionPending).reason,
        IncomingRevisionPendingReason.stale,
      );
    },
  );

  test(
    'a new Workspace at the same path has a distinct scope even when empty and complete',
    () async {
      final before = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      await success(b.close());
      if (Platform.isWindows) {
        await Process.run('attrib', [
          '-R',
          path.join(workspace('b'), '*'),
          '/S',
          '/D',
        ]);
      } else {
        await Process.run('chmod', ['-R', 'u+w', workspace('b')]);
      }
      await Directory(workspace('b')).delete(recursive: true);
      b = create('b');
      await success(b.open());
      final recreated = await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      );
      expect(
        recreated.identity.workspaceId,
        isNot(before.identity.workspaceId),
      );
      expect(recreated.snapshot.managedSkills, isEmpty);
      expect(recreated.isComplete, isTrue);
      expect(recreated.identity, isNot(before.identity));
    },
  );

  test(
    'two real Workspaces transfer exact upstream/effective IDs and complete history without auto Publish',
    () async {
      final baseline = await capture(b, bId);
      final initial = (await success(
        a.inspectPublishedHistory(PublishedHistoryRequest(managedSkillId: aId)),
      )).revisions.single.reference;
      expect(
        (await capture(a, aId)).currentEffective,
        baseline.currentEffective,
      );
      await publish(a, aId, 'published customization\n');
      await File(
        path.join(source.path, 'upstream.md'),
      ).writeAsString('upstream content\n');
      await success(a.update(UpdateRequest(managedSkillIds: {aId})));
      await success(
        a.restorePublish(
          RestorePublishRequest(managedSkillId: aId, selectedRevision: initial),
        ),
      );
      final firstRestore = await capture(a, aId);
      await success(
        a.restorePublish(
          RestorePublishRequest(managedSkillId: aId, selectedRevision: initial),
        ),
      );
      final incoming = await capture(a, aId);
      expect(incoming.contentHash, firstRestore.contentHash);
      expect(incoming.currentEffective, isNot(firstRestore.currentEffective));
      expect(incoming.currentUpstream, isNot(incoming.currentEffective));
      expect(incoming.publishedHistory.length, 5);
      expect(
        incoming.publishedHistory
            .where(
              (entry) => entry.kind == WorkspaceOperationKind.restorePublish,
            )
            .length,
        2,
      );
      final localIdentity = (await success(
        b.captureAuthoritativeState(const CaptureAuthoritativeStateRequest()),
      )).identity;
      final preparedIncoming = await success(
        b.prepareIncomingRevision(
          PrepareIncomingRevisionRequest(
            managedSkillId: bId,
            expectedIdentity: localIdentity,
            expectedRevision: b.snapshot.revision,
            contentManifest: incoming.wireManifest,
            packBytes: incoming.packBytes,
          ),
        ),
      );
      expect(preparedIncoming.identity, localIdentity);
      expect(preparedIncoming.currentEffective, incoming.currentEffective);
      final wire =
          jsonDecode(utf8.decode(preparedIncoming.wireManifest))
              as Map<String, Object?>;
      expect(wire.containsKey('workspaceIdentity'), isFalse);
      expect(wire.containsKey('packSha256'), isFalse);
      expect(
        ((wire['publishedHistory'] as List).first as Map)['publishedAtMicros'],
        isA<String>(),
      );
      final before = pointers('b', bId);
      // An unchanged Draft is rechecked and finalized through the existing flow.
      await success(b.ensureDraft(EnsureDraftRequest(managedSkillId: bId)));
      final outcome = await apply(preparedIncoming, baseline.currentEffective);
      expect(outcome, isA<IncomingRevisionApplied>());
      final after = pointers('b', bId), remote = pointers('a', aId);
      expect(after['effective_object_id'], remote['effective_object_id']);
      expect(after['upstream_object_id'], remote['upstream_object_id']);
      expect(after['source_lineage_id'], before['source_lineage_id']);
      expect(after['source_lineage_id'], isNot(remote['source_lineage_id']));
      expect(b.snapshot.findSkill(bId)!.draft, isNull);
      expect(
        b.snapshot.findSkill(bId)!.currentRevision.contentHash,
        incoming.contentHash,
      );
      final history = await success(
        b.inspectPublishedHistory(PublishedHistoryRequest(managedSkillId: bId)),
      );
      expect(history.revisions.length, 6);
      expect(
        history.revisions
            .where((entry) => entry.origin == PublishedRevisionOrigin.imported)
            .length,
        5,
      );
      final localOperations = await success(
        b.inspectOperationHistory(OperationHistoryRequest(managedSkillId: bId)),
      );
      expect(
        localOperations.entries
            .where(
              (entry) =>
                  entry.kind == WorkspaceOperationKind.applyIncomingRevision,
            )
            .length,
        1,
      );
      final reexported = await capture(b, bId);
      final importedIds = incoming.publishedHistory
          .map((entry) => entry.eventFingerprint)
          .toSet();
      expect(
        reexported.publishedHistory
            .map((entry) => entry.eventFingerprint)
            .toSet()
            .containsAll(importedIds),
        isTrue,
      );
      final pages = <PublishedRevisionReference>[];
      String? cursor;
      do {
        final page = await success(
          b.inspectPublishedHistory(
            PublishedHistoryRequest(
              managedSkillId: bId,
              cursor: cursor,
              limit: 1,
            ),
          ),
        );
        pages.addAll(page.revisions.map((entry) => entry.reference));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(pages.length, 6);
      expect(pages.toSet().length, 6);
      final importedRestore = history.revisions.firstWhere(
        (entry) =>
            entry.origin == PublishedRevisionOrigin.imported &&
            entry.kind == WorkspaceOperationKind.restorePublish,
      );
      final diff = await success(
        b.inspectDiff(
          InspectDiffRequest(
            managedSkillId: bId,
            to: importedRestore.reference,
          ),
        ),
      );
      expect(diff.files, isNotEmpty);
      final engine = RevisionNativeEngine.open();
      try {
        final nativeStore = path.join(
          workspace('b'),
          'revision-stores',
          '${bId.value}.git',
        );
        final manifest =
            jsonDecode(utf8.decode(incoming.wireManifest))
                as Map<String, Object?>;
        for (final entry in manifest['publishedHistory']! as List<Object?>) {
          final id = RevisionObjectId(
            (entry! as Map<String, Object?>)['revision']! as String,
          );
          engine.inspectCommit(nativeStore, id);
        }
      } finally {
        engine.close();
      }
      for (final name in ['a', 'b']) {
        final id = name == 'a' ? aId : bId;
        final exports = Directory(
          path.join(
            workspace(name),
            'revision-stores',
            '${id.value}.git',
            'export-artifacts',
          ),
        );
        if (await exports.exists()) {
          expect(await exports.list().toList(), isEmpty);
        }
      }
      expect(
        await apply(incoming, incoming.currentEffective),
        isA<IncomingRevisionUnchanged>(),
      );
      expect(pointers('b', bId), after);
      await success(
        b.restorePublish(
          RestorePublishRequest(
            managedSkillId: bId,
            selectedRevision: importedRestore.reference,
          ),
        ),
      );
      final restored = await capture(b, bId);
      expect(restored.currentEffective, isNot(incoming.currentEffective));
      expect(restored.contentHash, importedRestore.contentHash);
      expect(
        restored.publishedHistory
            .map((entry) => entry.eventFingerprint)
            .toSet()
            .containsAll(importedIds),
        isTrue,
      );
      await success(
        b.remove(
          RemoveRequest(
            managedSkillIds: {bId},
            intent: DestructiveIntent(reviewedRevision: b.snapshot.revision),
          ),
        ),
      );
      final check = sqlite3.open(
        path.join(workspace('b'), 'workspace.sqlite'),
        mode: OpenMode.readOnly,
      );
      expect(check.select('SELECT * FROM revision_published_events'), isEmpty);
      check.close();
    },
  );

  test(
    'dirty Draft and stale requests stay pending without changing selection',
    () async {
      final baseline = await capture(b, bId);
      await publish(a, aId, 'incoming\n');
      final incoming = await capture(a, aId);
      final draft = await success(
        b.ensureDraft(EnsureDraftRequest(managedSkillId: bId)),
      );
      await File(
        path.join(draft.path, 'notes.md'),
      ).writeAsString('keep dirty\n');
      final before = pointers('b', bId);
      final pending = await apply(incoming, baseline.currentEffective);
      expect(
        (pending as IncomingRevisionPending).reason,
        IncomingRevisionPendingReason.dirtyDraft,
      );
      expect(pointers('b', bId), before);
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        'keep dirty\n',
      );
      final stale = await success(
        b.applyIncomingRevision(
          ApplyIncomingRevisionRequest(
            managedSkillId: bId,
            expectedRevision: RepositoryRevision(0),
            expectedIdentity: baseline.identity,
            expectedEffective: baseline.currentEffective,
            incoming: incoming,
          ),
        ),
      );
      expect(
        (stale as IncomingRevisionPending).reason,
        IncomingRevisionPendingReason.stale,
      );
    },
  );

  test(
    'divergence preserves the local publication and does not create a Session or merge',
    () async {
      await publish(a, aId, 'a branch\n');
      await publish(b, bId, 'b branch\n');
      final before = pointers('b', bId);
      final baseline = await capture(b, bId);
      final result = await apply(
        await capture(a, aId),
        baseline.currentEffective,
      );
      expect(
        (result as IncomingRevisionPending).reason,
        IncomingRevisionPendingReason.diverged,
      );
      expect(pointers('b', bId), before);
      expect(b.snapshot.findSkill(bId)!.updateCandidate, isNull);
      expect(
        (await success(
          b.inspectPublishedHistory(
            PublishedHistoryRequest(managedSkillId: bId),
          ),
        )).revisions.length,
        2,
      );
    },
  );

  test(
    'a SQLite business-commit failure rolls materializations and selection back',
    () async {
      final baseline = await capture(b, bId);
      await publish(a, aId, 'incoming\n');
      final incoming = await capture(a, aId);
      final before = pointers('b', bId);
      final database = sqlite3.open(
        path.join(workspace('b'), 'workspace.sqlite'),
      );
      try {
        database.execute(
          "CREATE TRIGGER reject_incoming BEFORE UPDATE ON current_revision_selection BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
        );
      } finally {
        database.close();
      }
      final result = await b
          .applyIncomingRevision(
            ApplyIncomingRevisionRequest(
              managedSkillId: bId,
              expectedRevision: b.snapshot.revision,
              expectedIdentity: baseline.identity,
              expectedEffective: baseline.currentEffective,
              incoming: incoming,
            ),
          )
          .completed;
      expect(result, isA<SkillsFailure<IncomingRevisionApplyResult>>());
      expect(pointers('b', bId), before);
      expect(
        await File(
          path.join(
            workspace('b'),
            'repository-copies',
            'transfer-fixture',
            'notes.md',
          ),
        ).readAsString(),
        'base\n',
      );
    },
  );

  test(
    'tampered payload and bounded export do not change business state',
    () async {
      final baseline = await capture(b, bId);
      await publish(a, aId, 'incoming\n');
      final incoming = await capture(a, aId);
      final damaged = incoming.packBytes.toList()..[20] ^= 1;
      final invalid = CommittedRevisionBatch(
        identity: incoming.identity,
        packSha256: incoming.packSha256,
        indexSha256: incoming.indexSha256,
        source: incoming.source,
        slotKey: incoming.slotKey,
        contentHash: incoming.contentHash,
        currentUpstream: incoming.currentUpstream,
        currentEffective: incoming.currentEffective,
        publishedHistory: incoming.publishedHistory,
        wireManifest: incoming.wireManifest,
        packBytes: damaged,
        indexBytes: incoming.indexBytes,
      );
      final before = pointers('b', bId);
      final result = await apply(invalid, baseline.currentEffective);
      expect(
        (result as IncomingRevisionPending).reason,
        IncomingRevisionPendingReason.invalidPayload,
      );
      expect(pointers('b', bId), before);
      final limited = await a
          .exportCommittedRevision(
            ExportCommittedRevisionRequest(
              managedSkillId: aId,
              expectedRevision: a.snapshot.revision,
              maximumBytes: 1,
            ),
          )
          .completed;
      expect(limited, isA<SkillsFailure<CommittedRevisionBatch>>());
    },
  );
}
