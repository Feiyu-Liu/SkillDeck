import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/application/discovery/external_discovery_models.dart';
import 'package:skills_workspace/src/application/install/initial_import_models.dart';
import 'package:skills_workspace/src/application/install/initial_import_planner.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/agent_activation_ports.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/activation_selection.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';
import '../../support/install/initial_import_fakes.dart';
import '../../support/source/source_acquisition_fakes.dart';

void main() {
  late RecordingInitialRevisionCandidates revisions;
  late RecordingActivationOccupancyProbe occupancy;
  late FakeSourcePayloadEncoding payloads;
  late FakeSourceAcquisitionPorts sources;
  late InitialImportPlanner planner;

  setUp(() {
    revisions = RecordingInitialRevisionCandidates();
    occupancy = RecordingActivationOccupancyProbe();
    payloads = FakeSourcePayloadEncoding();
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionFailure<AcquiredSource>(
            code: SourceAcquisitionFailureCode.skillNotFound,
          ),
    );
    planner = _planner(
      revisions: revisions,
      occupancy: occupancy,
      payloads: payloads,
      sources: sources,
    );
  });

  test(
    'multi-Skill Install plans one candidate batch and exact provenance',
    () async {
      final local = LocalSourceDescriptor(
        locator: _fixturePath('source'),
        skillPath: 'one',
      );
      final wellKnown = WellKnownSourceDescriptor(
        locator: 'https://example.test/index.json',
        skillPath: 'two',
      );

      final preflight = await planner.planInstall(
        snapshot: RepositorySnapshot.empty(),
        acquiredSource: AcquiredSource(
          canonicalSource: LocalSourceDescriptor(
            locator: _fixturePath('source'),
          ),
          resolvedSourceRevision: 'source-revision',
          skills: [
            _skill(local, slotKey: 'one', hashCharacter: 'a'),
            _skill(wellKnown, slotKey: 'two', hashCharacter: 'b'),
          ],
        ),
        activationSelection: const ActivationSelection.none(),
        activationMode: RequestedActivationMode.copy,
      );

      final result = await _prepareAndAssemble(planner, preflight.valueOrNull!);
      final plan = result.valueOrNull!;
      expect(revisions.calls, 1);
      expect(revisions.lastIntents, hasLength(2));
      expect(
        revisions.lastIntents.map((intent) => intent.resolvedSourceRevision),
        everyElement('source-revision'),
      );
      expect(payloads.encodedSources, [local, wellKnown]);
      expect(plan.affectedSkillIds, hasLength(2));
      expect(plan.revisionSelectionChanges, hasLength(2));
      expect(plan.recoveryIntents, hasLength(2));
      expect(
        plan.materializationIntents
            .whereType<RepositoryCopyMaterializationIntent>(),
        hasLength(2),
      );
      expect(
        plan.businessChanges.mutations.whereType<PutManagedSkill>(),
        hasLength(2),
      );
      expect(
        plan.businessChanges.mutations.whereType<PutSkillSource>(),
        hasLength(2),
      );
      expect(
        plan.businessChanges.mutations.whereType<PutRevisionMetadata>(),
        hasLength(2),
      );
    },
  );

  test(
    'duplicate Slot rejects before IDs, revision candidates, and writes',
    () async {
      final source = LocalSourceDescriptor(locator: _fixturePath('source'));

      final result = await planner.planInstall(
        snapshot: RepositorySnapshot.empty(),
        acquiredSource: AcquiredSource(
          canonicalSource: source,
          skills: [
            _skill(source, slotKey: 'same', hashCharacter: 'a'),
            _skill(source, slotKey: 'same', hashCharacter: 'b'),
          ],
        ),
        activationSelection: const ActivationSelection.none(),
        activationMode: RequestedActivationMode.copy,
      );

      expect(
        result.failureOrNull?.code,
        InitialImportFailureCode.duplicateSkillSlot,
      );
      expect(revisions.calls, 0);
      expect(payloads.encodedSources, isEmpty);
    },
  );

  test(
    'dirty Draft collision wins before revision candidate preparation',
    () async {
      final source = LocalSourceDescriptor(locator: _fixturePath('source'));

      final result = await planner.planInstall(
        snapshot: RepositorySnapshot(
          revision: RepositoryRevision(4),
          managedSkills: [_managedSkill(dirtyDraft: true)],
        ),
        acquiredSource: AcquiredSource(
          canonicalSource: source,
          skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
        ),
        activationSelection: const ActivationSelection.none(),
        activationMode: RequestedActivationMode.copy,
      );

      expect(
        result.failureOrNull?.code,
        InitialImportFailureCode.dirtyDraftResolutionRequired,
      );
      expect(revisions.calls, 0);
      expect(sources.calls, isEmpty);
    },
  );

  test(
    'occupied Install target returns a stale-safe takeover with zero writes',
    () async {
      final source = LocalSourceDescriptor(locator: _fixturePath('source'));
      final targetPath = path.join(_fixturePath('agent/skills'), 'one');
      occupancy.results[targetPath] = _occupancy(
        targetPath,
        relation: InspectedActivationContentRelation.matchesCurrentRevision,
      );

      final result = await planner.planInstall(
        snapshot: RepositorySnapshot.empty(),
        acquiredSource: AcquiredSource(
          canonicalSource: source,
          skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
        ),
        activationSelection: ActivationSelection.explicit([
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        activationMode: RequestedActivationMode.copy,
      );

      final takeover = result.takeoverOrNull!;
      expect(takeover.occupancies.single.targetPath, targetPath);
      expect(takeover.fingerprintsByTargetPath, {targetPath: 'fingerprint'});
      expect(
        takeover.preflight.subjects.single.targets.single.mustExist,
        isTrue,
      );
      expect(revisions.calls, 0);

      final confirmed = await planner.planInstall(
        snapshot: RepositorySnapshot.empty(),
        acquiredSource: AcquiredSource(
          canonicalSource: source,
          skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
        ),
        activationSelection: ActivationSelection.explicit([
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        activationMode: RequestedActivationMode.copy,
        confirmedTakeoverFingerprints: takeover.fingerprintsByTargetPath,
        expectedTargetSignatures: takeover.targetSignatures,
      );
      expect(confirmed.valueOrNull, isNotNull);
      expect(confirmed.takeoverOrNull, isNull);
    },
  );

  test('changed Install takeover target is stale', () async {
    final source = LocalSourceDescriptor(locator: _fixturePath('source'));
    final targetPath = path.join(_fixturePath('agent/skills'), 'one');
    occupancy.results[targetPath] = _occupancy(
      targetPath,
      relation: InspectedActivationContentRelation.indeterminate,
      fingerprint: 'reviewed',
    );
    final first = await planner.planInstall(
      snapshot: RepositorySnapshot.empty(),
      acquiredSource: AcquiredSource(
        canonicalSource: source,
        skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
      ),
      activationSelection: ActivationSelection.explicit([
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      activationMode: RequestedActivationMode.copy,
    );
    occupancy.results[targetPath] = _occupancy(
      targetPath,
      relation: InspectedActivationContentRelation.indeterminate,
      fingerprint: 'changed',
    );

    final confirmed = await planner.planInstall(
      snapshot: RepositorySnapshot.empty(),
      acquiredSource: AcquiredSource(
        canonicalSource: source,
        skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
      ),
      activationSelection: ActivationSelection.explicit([
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      activationMode: RequestedActivationMode.copy,
      confirmedTakeoverFingerprints:
          first.takeoverOrNull!.fingerprintsByTargetPath,
      expectedTargetSignatures: first.takeoverOrNull!.targetSignatures,
    );

    expect(
      confirmed.failureOrNull?.code,
      InitialImportFailureCode.staleInstallTakeover,
    );
    expect(
      confirmed.failureOrNull?.context['reason'],
      'activationTargetChanged',
    );
    expect(revisions.calls, 0);
  });

  test('pre-cancelled Install performs no adapter or candidate work', () async {
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final source = LocalSourceDescriptor(locator: _fixturePath('source'));

    final result = await planner.planInstall(
      snapshot: RepositorySnapshot.empty(),
      acquiredSource: AcquiredSource(
        canonicalSource: source,
        skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
      ),
      activationSelection: const ActivationSelection.none(),
      activationMode: RequestedActivationMode.copy,
      cancellationToken: cancellation.token,
    );

    expect(
      result.failureOrNull?.code,
      InitialImportFailureCode.operationCancelled,
    );
    expect(revisions.calls, 0);
    expect(occupancy.inspectedPaths, isEmpty);
  });

  test(
    'Adoption reacquires authoritative bytes and replaces all occurrences',
    () async {
      final candidate = _candidate();
      final occurrences = _occurrences(hashCharacter: 'a');
      final scan = _scan(candidate, occurrences);
      final authoritativeSource = occurrences.first.source;
      sources = FakeSourceAcquisitionPorts((
        source,
        selection,
        options,
        cancellationToken,
      ) async {
        expect(source, authoritativeSource);
        return SourceAcquisitionSuccess<AcquiredSource>(
          value: AcquiredSource(
            canonicalSource: source,
            skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
          ),
        );
      });
      for (final occurrence in occurrences) {
        occupancy.results[occurrence.skillLocation] = _occupancy(
          occurrence.skillLocation,
          relation: InspectedActivationContentRelation.matchesCurrentRevision,
          fingerprint: 'fingerprint-${occurrence.target.agentIds.single}',
          existingContentHash: _hash('a'),
        );
      }
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      final preflight = await planner.planAdoption(
        snapshot: RepositorySnapshot.empty(),
        selection: _candidateSelection(
          candidate,
          occurrences.first.skillLocation,
        ),
        scan: scan,
      );

      final result = await _prepareAndAssemble(planner, preflight.valueOrNull!);
      final plan = result.valueOrNull!;
      expect(plan.kind, InitialImportKind.adoption);
      expect(revisions.calls, 1);
      expect(
        payloads.encodedSources.single,
        isA<AdoptedSnapshotSourceDescriptor>(),
      );
      final adopted =
          payloads.encodedSources.single as AdoptedSnapshotSourceDescriptor;
      expect(adopted.authoritativeLocation, occurrences.first.skillLocation);
      expect(adopted.contentHash, _hash('a'));
      final activations = plan.materializationIntents
          .whereType<ActivationMaterializationIntent>()
          .toList();
      expect(activations, hasLength(2));
      expect(
        activations,
        everyElement(
          predicate<ActivationMaterializationIntent>(
            (intent) =>
                intent.replaceExisting &&
                intent.expectedExistingFingerprint != null,
          ),
        ),
      );
      expect(
        plan.businessChanges.mutations.whereType<PutActivation>(),
        hasLength(2),
      );
    },
  );

  for (final sameObject in [true, false]) {
    test(
      sameObject
          ? 'Adoption treats a case-aliased destination as the reviewed occurrence'
          : 'Adoption with an undiscovered occupant at the destination returns a takeover',
      () async {
        // On Windows, case-only spellings have the same lexical identity.
        // The unreviewed occupant must be a genuinely different folder.
        final existingFolder = sameObject ? 'UpperCase' : 'different-folder';
        final existingPath = path.join(
          _fixturePath('agent/skills'),
          existingFolder,
        );
        final targetPath = path.join(_fixturePath('agent/skills'), 'uppercase');
        final occurrence = _occurrence(
          agentId: 'agent',
          root: _fixturePath('agent/skills'),
          hashCharacter: 'a',
          slotKey: 'uppercase',
          folderName: existingFolder,
        );
        final candidate = ExternalSkillCandidate(
          slotKey: 'uppercase',
          declaredName: 'uppercase',
          description: 'uppercase description',
          contentHash: _hash('a'),
          locations: [existingPath],
          agentIds: const ['agent'],
        );
        sources = FakeSourceAcquisitionPorts(
          (source, selection, options, cancellationToken) async =>
              SourceAcquisitionSuccess<AcquiredSource>(
                value: AcquiredSource(
                  canonicalSource: source,
                  skills: [
                    _skill(source, slotKey: 'uppercase', hashCharacter: 'a'),
                  ],
                ),
              ),
        );
        for (final location in [existingPath, targetPath]) {
          occupancy.results[location] = _occupancy(
            location,
            relation: InspectedActivationContentRelation.matchesCurrentRevision,
            existingContentHash: _hash('a'),
          );
        }
        planner = _planner(
          revisions: revisions,
          occupancy: occupancy,
          payloads: payloads,
          sources: sources,
          identity: _fixtureIdentity(
            sameObjectPairs: {if (sameObject) (targetPath, existingPath)},
          ),
        );

        final planned = await planner.planAdoption(
          snapshot: RepositorySnapshot.empty(),
          selection: _candidateSelection(candidate, existingPath),
          scan: _scan(candidate, [occurrence]),
        );

        expect(planned.failureOrNull, isNull);
        if (sameObject) {
          expect(planned.takeoverOrNull, isNull);
          final subject = planned.valueOrNull!.subjects.single;
          expect(subject.targets, hasLength(1));
          expect(subject.targets.single.mustExist, isTrue);
          expect(subject.targets.single.targetPath, existingPath);
          expect(
            subject.targets.single.expectedExistingContentHash,
            _hash('a'),
          );
          expect(subject.retirements, isEmpty);
          expect(occupancy.inspectedPaths, [existingPath]);
        } else {
          expect(planned.takeoverOrNull, isNotNull);
          expect(
            planned.takeoverOrNull!.occupancies.single.targetPath,
            targetPath,
          );
          expect(planned.valueOrNull, isNull);
        }
        expect(revisions.calls, 0);
      },
    );
  }

  for (final rootsResolveTogether in [true, false]) {
    test(
      rootsResolveTogether
          ? 'Adoption through two roots that are one directory plans one target'
          : 'Adoption rejects two targets that collide on one path',
      () async {
        // Like a dotfiles `~/.agents/skills -> ~/.claude/skills`, the second
        // Agent's root is a link to the first Agent's folder, so the scanner
        // sees the same folder through both roots.
        final linkedRoot = _fixturePath('agent-two/skills');
        final physicalRoot = _fixturePath('agent/skills');
        final physicalPath = path.join(physicalRoot, 'shared');
        final linkedPath = path.join(linkedRoot, 'shared');
        final throughLink = _occurrence(
          agentId: 'agent-two',
          root: linkedRoot,
          hashCharacter: 'a',
          slotKey: 'shared',
          mutationPath: physicalPath,
        );
        final direct = _occurrence(
          agentId: 'agent',
          root: physicalRoot,
          hashCharacter: 'a',
          slotKey: 'shared',
        );
        final candidate = ExternalSkillCandidate(
          slotKey: 'shared',
          declaredName: 'shared',
          description: 'shared description',
          contentHash: _hash('a'),
          locations: [linkedPath, physicalPath],
          agentIds: const ['agent', 'agent-two'],
        );
        sources = FakeSourceAcquisitionPorts(
          (source, selection, options, cancellationToken) async =>
              SourceAcquisitionSuccess<AcquiredSource>(
                value: AcquiredSource(
                  canonicalSource: source,
                  skills: [
                    _skill(source, slotKey: 'shared', hashCharacter: 'a'),
                  ],
                ),
              ),
        );
        occupancy.results[physicalPath] = _occupancy(
          physicalPath,
          relation: InspectedActivationContentRelation.matchesCurrentRevision,
          existingContentHash: _hash('a'),
        );
        planner = _planner(
          revisions: revisions,
          occupancy: occupancy,
          payloads: payloads,
          sources: sources,
          identity: _fixtureIdentity(
            resolvedDirectories: {
              if (rootsResolveTogether) linkedRoot: physicalRoot,
            },
          ),
        );

        final planned = await planner.planAdoption(
          snapshot: RepositorySnapshot.empty(),
          selection: _candidateSelection(candidate, physicalPath),
          scan: _scan(candidate, [throughLink, direct]),
        );

        if (!rootsResolveTogether) {
          final failure = planned.failureOrNull!;
          expect(failure.code, InitialImportFailureCode.activationUnavailable);
          expect(failure.context, <String, Object?>{
            'reason': 'activationTargetsCollide',
            'slotKey': 'shared',
            'targetPath': physicalPath,
            'agentIds': <String>['agent-two', 'agent'],
          });
          expect(revisions.calls, 0);
          return;
        }
        expect(planned.failureOrNull, isNull);
        expect(planned.takeoverOrNull, isNull);
        final subject = planned.valueOrNull!.subjects.single;
        final target = subject.targets.single;
        expect(target.targetPath, physicalPath);
        expect(target.mustExist, isTrue);
        expect(target.target.location, physicalRoot);
        expect(target.target.agentIds, <String>['agent', 'agent-two']);
        expect(subject.retirements, isEmpty);
        expect(occupancy.inspectedPaths, [physicalPath]);
        expect(
          planned.valueOrNull!.activationWarnings.single.code,
          ActivationWarningCode.sharedActivationLocation,
        );

        final result = await _prepareAndAssemble(planner, planned.valueOrNull!);
        final activations = result.valueOrNull!.businessChanges.mutations
            .whereType<PutActivation>()
            .toList();
        expect(activations, hasLength(1));
        expect(activations.single.canonicalPath, physicalRoot);
        expect(activations.single.agentIds, <String>['agent', 'agent-two']);
        expect(revisions.calls, 1);
      },
    );
  }

  test(
    'Conflict Adoption uses the selected authority for every occurrence',
    () async {
      final occurrences = _divergentOccurrences();
      final conflict = _conflict(occurrences);
      sources = FakeSourceAcquisitionPorts((
        source,
        selection,
        options,
        cancellationToken,
      ) async {
        final hash = source == occurrences.first.source ? 'a' : 'b';
        return SourceAcquisitionSuccess<AcquiredSource>(
          value: AcquiredSource(
            canonicalSource: source,
            skills: [_skill(source, slotKey: 'one', hashCharacter: hash)],
          ),
        );
      });
      for (final occurrence in occurrences) {
        occupancy.results[occurrence.skillLocation] = _occupancy(
          occurrence.skillLocation,
          relation:
              InspectedActivationContentRelation.differsFromCurrentRevision,
          fingerprint: 'fingerprint-${occurrence.target.agentIds.single}',
          existingContentHash: occurrence.skill.contentHash,
        );
      }
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      for (final authority in occurrences) {
        final selection = ExternalAdoptionSelection.fromConflict(
          conflict,
          authority.skillLocation,
        );
        final preflight = await planner.planAdoption(
          snapshot: RepositorySnapshot.empty(),
          selection: selection,
          scan: _conflictScan(conflict, occurrences),
        );

        expect(preflight.failureOrNull, isNull);
        expect(
          preflight.valueOrNull!.revisionIntents.single.tree.contentHash,
          authority.skill.contentHash,
        );
        expect(
          preflight.valueOrNull!.subjects.single.targets.map(
            (target) => target.expectedExistingContentHash,
          ),
          unorderedEquals(
            occurrences.map((occurrence) => occurrence.skill.contentHash),
          ),
        );
      }

      expect(sources.calls, <SourceDescriptor>[
        occurrences.first.source,
        occurrences.last.source,
      ]);
      expect(revisions.calls, 0);
    },
  );

  test('Adoption resolves automatic symbolic-link targets', () async {
    final candidate = _candidate();
    final occurrences = _occurrences(hashCharacter: 'a');
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: AcquiredSource(
              canonicalSource: source,
              skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
            ),
          ),
    );
    for (final occurrence in occurrences) {
      occupancy.results[occurrence.skillLocation] = _occupancy(
        occurrence.skillLocation,
        relation: InspectedActivationContentRelation.matchesCurrentRevision,
        existingContentHash: _hash('a'),
      );
    }
    planner = _planner(
      revisions: revisions,
      occupancy: occupancy,
      payloads: payloads,
      sources: sources,
      symbolicLinks: true,
    );

    final preflight = await planner.planAdoption(
      snapshot: RepositorySnapshot.empty(),
      selection: _candidateSelection(
        candidate,
        occurrences.first.skillLocation,
      ),
      scan: _scan(candidate, occurrences),
      activationMode: RequestedActivationMode.automatic,
    );

    expect(
      preflight.valueOrNull!.subjects.single.targets.map(
        (target) => target.target.mode,
      ),
      everyElement(ActivationMode.symbolicLink),
    );
  });

  test(
    'Conflict Adoption rejects a changed reviewed occurrence before preparation',
    () async {
      final reviewedOccurrences = _divergentOccurrences();
      final currentOccurrences = <ExternalSkillOccurrence>[
        reviewedOccurrences.first,
        _occurrence(
          agentId: 'agent-two',
          root: _fixturePath('agent-two/skills'),
          hashCharacter: 'c',
        ),
      ];
      final conflict = _conflict(reviewedOccurrences);
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      final result = await planner.planAdoption(
        snapshot: RepositorySnapshot.empty(),
        selection: ExternalAdoptionSelection.fromConflict(
          conflict,
          reviewedOccurrences.first.skillLocation,
        ),
        scan: _conflictScan(conflict, currentOccurrences),
      );

      expect(
        result.failureOrNull?.code,
        InitialImportFailureCode.staleExternalCandidate,
      );
      expect(
        result.failureOrNull?.context['reason'],
        'reviewedLocationsChanged',
      );
      expect(sources.calls, isEmpty);
      expect(revisions.calls, 0);
    },
  );

  test(
    'Conflict Adoption rejects added and removed reviewed locations',
    () async {
      final occurrences = _divergentOccurrences();
      final conflict = _conflict(occurrences);
      final selection = ExternalAdoptionSelection.fromConflict(
        conflict,
        occurrences.first.skillLocation,
      );
      final variants = <List<ExternalSkillOccurrence>>[
        <ExternalSkillOccurrence>[occurrences.first],
        <ExternalSkillOccurrence>[
          ...occurrences,
          _occurrence(
            agentId: 'agent-three',
            root: _fixturePath('agent-three/skills'),
            hashCharacter: 'a',
          ),
        ],
      ];
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      for (final current in variants) {
        final result = await planner.planAdoption(
          snapshot: RepositorySnapshot.empty(),
          selection: selection,
          scan: _conflictScan(conflict, current),
        );

        expect(
          result.failureOrNull?.code,
          InitialImportFailureCode.staleExternalCandidate,
        );
        expect(
          result.failureOrNull?.context['reason'],
          'reviewedLocationsChanged',
        );
      }
      expect(sources.calls, isEmpty);
      expect(revisions.calls, 0);
    },
  );

  test(
    'Conflict Adoption rejects reviewed locations that normalize together',
    () async {
      final selection = ExternalAdoptionSelection(
        slotKey: 'one',
        reviewedContentHashByLocation: <String, String>{
          _fixturePath('agent/skills/one'): _hash('a'),
          _fixturePath('agent/skills/./one'): _hash('a'),
        },
        authoritativeLocation: _fixturePath('agent/skills/one'),
      );
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      final result = await planner.planAdoption(
        snapshot: RepositorySnapshot.empty(),
        selection: selection,
        scan: _conflictScan(
          _conflict(_divergentOccurrences()),
          _divergentOccurrences(),
        ),
      );

      expect(
        result.failureOrNull?.code,
        InitialImportFailureCode.staleExternalCandidate,
      );
      expect(
        result.failureOrNull?.context['reason'],
        'reviewedLocationsAmbiguous',
      );
      expect(sources.calls, isEmpty);
      expect(revisions.calls, 0);
    },
  );

  test(
    'Conflict Adoption rejects a non-authoritative target changed after review',
    () async {
      final occurrences = _divergentOccurrences();
      final conflict = _conflict(occurrences);
      sources = FakeSourceAcquisitionPorts(
        (source, selection, options, cancellationToken) async =>
            SourceAcquisitionSuccess<AcquiredSource>(
              value: AcquiredSource(
                canonicalSource: source,
                skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
              ),
            ),
      );
      occupancy.results[occurrences.first.skillLocation] = _occupancy(
        occurrences.first.skillLocation,
        relation: InspectedActivationContentRelation.matchesCurrentRevision,
        existingContentHash: 'a' * 64,
      );
      occupancy.results[occurrences.last.skillLocation] = _occupancy(
        occurrences.last.skillLocation,
        relation: InspectedActivationContentRelation.differsFromCurrentRevision,
        existingContentHash: 'c' * 64,
      );
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      final result = await planner.planAdoption(
        snapshot: RepositorySnapshot.empty(),
        selection: ExternalAdoptionSelection.fromConflict(
          conflict,
          occurrences.first.skillLocation,
        ),
        scan: _conflictScan(conflict, occurrences),
      );

      expect(
        result.failureOrNull?.code,
        InitialImportFailureCode.staleExternalCandidate,
      );
      expect(result.failureOrNull?.context['reason'], 'externalContentChanged');
      expect(revisions.calls, 0);
    },
  );

  test(
    'Adoption rejects changed authoritative content before preparation',
    () async {
      final candidate = _candidate();
      final occurrences = _occurrences(hashCharacter: 'a');
      sources = FakeSourceAcquisitionPorts(
        (source, selection, options, cancellationToken) async =>
            SourceAcquisitionSuccess<AcquiredSource>(
              value: AcquiredSource(
                canonicalSource: source,
                skills: [_skill(source, slotKey: 'one', hashCharacter: 'b')],
              ),
            ),
      );
      planner = _planner(
        revisions: revisions,
        occupancy: occupancy,
        payloads: payloads,
        sources: sources,
      );

      final result = await planner.planAdoption(
        snapshot: RepositorySnapshot.empty(),
        selection: _candidateSelection(
          candidate,
          occurrences.first.skillLocation,
        ),
        scan: _scan(candidate, occurrences),
      );

      expect(
        result.failureOrNull?.code,
        InitialImportFailureCode.staleExternalCandidate,
      );
      expect(
        result.failureOrNull?.context['reason'],
        'authoritativeContentChanged',
      );
      expect(revisions.calls, 0);
    },
  );

  test('Adoption rejects disappeared occupancy before preparation', () async {
    final candidate = _candidate();
    final occurrences = _occurrences(hashCharacter: 'a');
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: AcquiredSource(
              canonicalSource: source,
              skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
            ),
          ),
    );
    planner = _planner(
      revisions: revisions,
      occupancy: occupancy,
      payloads: payloads,
      sources: sources,
    );

    final result = await planner.planAdoption(
      snapshot: RepositorySnapshot.empty(),
      selection: _candidateSelection(
        candidate,
        occurrences.first.skillLocation,
      ),
      scan: _scan(candidate, occurrences),
    );

    expect(
      result.failureOrNull?.code,
      InitialImportFailureCode.staleExternalCandidate,
    );
    expect(
      result.failureOrNull?.context['reason'],
      'externalTargetDisappeared',
    );
    expect(revisions.calls, 0);
  });

  test('source payload rejection cannot reach revision preparation', () async {
    payloads.failure = SourcePayloadEncodingFailureCode.credentialRejected;
    final source = GitSourceDescriptor(
      locator: 'https://example.test/source.git',
    );

    final result = await planner.planInstall(
      snapshot: RepositorySnapshot.empty(),
      acquiredSource: AcquiredSource(
        canonicalSource: source,
        skills: [_skill(source, slotKey: 'one', hashCharacter: 'a')],
      ),
      activationSelection: const ActivationSelection.none(),
      activationMode: RequestedActivationMode.copy,
    );

    expect(
      result.failureOrNull?.code,
      InitialImportFailureCode.sourcePayloadInvalid,
    );
    expect(revisions.calls, 0);
  });

  test('candidate batch failure returns no partial business plan', () async {
    revisions.failure = InitialRevisionPreparationFailureCode.ioFailure;
    final source = LocalSourceDescriptor(locator: _fixturePath('source'));

    final preflight = await planner.planInstall(
      snapshot: RepositorySnapshot.empty(),
      acquiredSource: AcquiredSource(
        canonicalSource: source,
        skills: [
          _skill(source, slotKey: 'one', hashCharacter: 'a'),
          _skill(source, slotKey: 'two', hashCharacter: 'b'),
        ],
      ),
      activationSelection: const ActivationSelection.none(),
      activationMode: RequestedActivationMode.copy,
    );

    final result = await _prepareAndAssemble(planner, preflight.valueOrNull!);
    expect(
      result.failureOrNull?.code,
      InitialImportFailureCode.revisionPreparationFailed,
    );
    expect(revisions.calls, 1);
    expect(revisions.lastIntents, hasLength(2));
    expect(result.valueOrNull, isNull);
  });

  test(
    'two Skills may persist Activations under the same Agent root',
    () async {
      final source = LocalSourceDescriptor(locator: _fixturePath('source'));

      final preflight = await planner.planInstall(
        snapshot: RepositorySnapshot.empty(),
        acquiredSource: AcquiredSource(
          canonicalSource: source,
          skills: [
            _skill(source, slotKey: 'one', hashCharacter: 'a'),
            _skill(source, slotKey: 'two', hashCharacter: 'b'),
          ],
        ),
        activationSelection: ActivationSelection.explicit([
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        activationMode: RequestedActivationMode.copy,
      );

      final result = await _prepareAndAssemble(planner, preflight.valueOrNull!);
      expect(
        result.valueOrNull!.businessChanges.mutations
            .whereType<PutActivation>()
            .map((mutation) => mutation.canonicalPath),
        [_fixturePath('agent/skills'), _fixturePath('agent/skills')],
      );
      expect(occupancy.inspectedPaths, [
        path.join(_fixturePath('agent/skills'), 'one'),
        path.join(_fixturePath('agent/skills'), 'two'),
      ]);
    },
  );
}

Future<InitialImportPlanningResult<InitialImportPlan>> _prepareAndAssemble(
  InitialImportPlanner planner,
  InitialImportPreflight preflight,
) {
  final operationId = OperationId('10000000-0000-4000-8000-000000000001');
  final envelope = PreparedOperationEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: preflight.snapshotRevision,
    committedRepositoryRevision: preflight.snapshotRevision.next(),
    operationGeneration: preflight.snapshotRevision.next().value,
    preparationSteps: <PreparationOperationStep>[
      for (final subject in preflight.subjects) ...<PreparationOperationStep>[
        PreparationOperationStep(
          stepId: 'candidate-${subject.managedSkillId.value}',
          recoveryReference: RecoveryReference(
            'candidate-${subject.managedSkillId.value}',
          ),
          kind: PreparationStepKind.revisionCandidate,
        ),
        PreparationOperationStep(
          stepId: 'bundle-${subject.managedSkillId.value}',
          recoveryReference: RecoveryReference(
            'bundle-${subject.managedSkillId.value}',
          ),
          kind: PreparationStepKind.revisionBundle,
        ),
      ],
    ],
    record: OperationRecordPlan(
      operationId: operationId,
      kind: preflight.kind.name,
      subjects: const <OperationSubjectPlan>[],
      retainWithoutSubjects: true,
    ),
  );
  return planner.prepareAndAssemble(preflight: preflight, envelope: envelope);
}

InitialImportPlanner _planner({
  required RecordingInitialRevisionCandidates revisions,
  required RecordingActivationOccupancyProbe occupancy,
  required FakeSourcePayloadEncoding payloads,
  required FakeSourceAcquisitionPorts sources,
  bool symbolicLinks = false,
  ActivationLocationIdentityPort? identity,
}) {
  final locationIdentity = identity ?? _fixtureIdentity();
  final catalog = AgentCatalog.create(
    platform: DesktopPlatform.macos,
    detectionPort: FakeAgentDetectionPort(),
    builtIns: [
      AgentDefinition(
        id: 'agent',
        displayName: 'Agent',
        platforms: {
          DesktopPlatform.macos: AgentPlatformDefinition(
            globalSkillsPath: _fixturePath('agent/skills'),
          ),
        },
      ),
      AgentDefinition(
        id: 'agent-two',
        displayName: 'Agent Two',
        platforms: {
          DesktopPlatform.macos: AgentPlatformDefinition(
            globalSkillsPath: _fixturePath('agent-two/skills'),
          ),
        },
      ),
    ],
  ).valueOrNull!;
  return InitialImportPlanner(
    sourceAcquisition: SourceAcquisitionCoordinator(
      local: sources,
      git: sources,
      wellKnown: sources,
    ),
    activationTargetResolver: ActivationTargetResolver(
      catalog: catalog,
      symbolicLinkCapability: FakeSymbolicLinkCapability(
        defaultResult: symbolicLinks,
      ),
      locationIdentity: locationIdentity,
    ),
    occupancyProbe: occupancy,
    locationIdentity: locationIdentity,
    identities: SequenceWorkspaceEntityIdentities(),
    sourcePayloads: payloads,
    revisionCandidates: revisions,
    clock: () => DateTime.utc(2026, 8, 17),
  );
}

// Absolute filesystem fixtures use the host grammar, just like the planner's
// path.join and AgentCatalog.resolve. Git skillPath values remain POSIX-relative.
String _fixturePath(String relative) => path.joinAll([
  Platform.isWindows ? r'C:\' : '/',
  ...path.posix.split(relative),
]);

// Match the planner's host-native paths, including Windows case folding.
ActivationLocationIdentityPort _fixtureIdentity({
  Set<(String, String)> sameObjectPairs = const {},
  Map<String, String> resolvedDirectories = const {},
}) => Platform.isWindows
    ? WindowsActivationLocationIdentity(
        sameObjectPairs: sameObjectPairs,
        resolvedDirectories: resolvedDirectories,
      )
    : PosixActivationLocationIdentity(
        sameObjectPairs: sameObjectPairs,
        resolvedDirectories: resolvedDirectories,
      );

AcquiredSourceSkill _skill(
  SourceDescriptor source, {
  required String slotKey,
  required String hashCharacter,
}) => AcquiredSourceSkill(
  provenance: source,
  declaredName: slotKey,
  description: '$slotKey description',
  slotKey: slotKey,
  skillPath: slotKey,
  frontmatter: <String, Object?>{
    'name': slotKey,
    'description': '$slotKey description',
  },
  tree: NormalizedSkillTree(
    files: [
      NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: [1],
        isExecutable: false,
      ),
    ],
    contentHash: _hash(hashCharacter),
    byteSize: 1,
  ),
);

ManagedSkill _managedSkill({required bool dirtyDraft}) => ManagedSkill(
  id: ManagedSkillId('00000000-0000-4000-8000-000000000999'),
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'one',
  description: 'one description',
  source: LocalSourceDescriptor(locator: _fixturePath('old-source')),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _hash('a'),
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026, 8, 16),
  ),
  draft: DraftSummary(
    purpose: DraftPurpose.customization,
    path: _fixturePath('workspace/drafts/one'),
    isDirty: dirtyDraft,
    updatedAt: DateTime.utc(2026, 8, 16),
  ),
);

ExternalSkillCandidate _candidate() => ExternalSkillCandidate(
  slotKey: 'one',
  declaredName: 'one',
  description: 'one description',
  contentHash: _hash('a'),
  locations: [
    _fixturePath('agent/skills/one'),
    _fixturePath('agent-two/skills/one'),
  ],
  agentIds: const ['agent', 'agent-two'],
);

ExternalAdoptionSelection _candidateSelection(
  ExternalSkillCandidate candidate,
  String authoritativeLocation,
) => ExternalAdoptionSelection.fromCandidate(candidate, authoritativeLocation);

List<ExternalSkillOccurrence> _occurrences({required String hashCharacter}) => [
  _occurrence(
    agentId: 'agent',
    root: _fixturePath('agent/skills'),
    hashCharacter: hashCharacter,
  ),
  _occurrence(
    agentId: 'agent-two',
    root: _fixturePath('agent-two/skills'),
    hashCharacter: hashCharacter,
  ),
];

List<ExternalSkillOccurrence> _divergentOccurrences() =>
    <ExternalSkillOccurrence>[
      _occurrence(
        agentId: 'agent',
        root: _fixturePath('agent/skills'),
        hashCharacter: 'a',
      ),
      _occurrence(
        agentId: 'agent-two',
        root: _fixturePath('agent-two/skills'),
        hashCharacter: 'b',
      ),
    ];

ExternalSkillOccurrence _occurrence({
  required String agentId,
  required String root,
  required String hashCharacter,
  String slotKey = 'one',
  String? folderName,
  String? mutationPath,
}) => ExternalSkillOccurrence(
  skill: ScannedExternalSkill(
    declaredName: slotKey,
    description: '$slotKey description',
    slotKey: slotKey,
    contentHash: _hash(hashCharacter),
    skillLocation: path.join(root, folderName ?? slotKey),
    mutationPath: mutationPath,
    source: LocalSourceDescriptor(
      locator: root,
      skillPath: folderName ?? slotKey,
    ),
  ),
  target: ResolvedExternalSkillLocation(
    location: root,
    canonicalTargets: <ResolvedActivationTarget>[
      ResolvedActivationTarget(
        location: root,
        scope: ActivationScope.global,
        mode: ActivationMode.copy,
        agentIds: [agentId],
      ),
    ],
  ),
);

ExternalSkillScan _scan(
  ExternalSkillCandidate candidate,
  List<ExternalSkillOccurrence> occurrences,
) => ExternalSkillScan(
  discovery: ExternalSkillsDiscovery(
    candidates: [candidate],
    conflicts: const [],
  ),
  occurrencesBySlot: {candidate.slotKey: occurrences},
);

ExternalSkillConflict _conflict(List<ExternalSkillOccurrence> occurrences) =>
    ExternalSkillConflict(
      slotKey: 'one',
      contentHashByLocation: <String, String>{
        for (final occurrence in occurrences)
          occurrence.skillLocation: occurrence.skill.contentHash,
      },
    );

ExternalSkillScan _conflictScan(
  ExternalSkillConflict conflict,
  List<ExternalSkillOccurrence> occurrences,
) => ExternalSkillScan(
  discovery: ExternalSkillsDiscovery(
    candidates: const <ExternalSkillCandidate>[],
    conflicts: <ExternalSkillConflict>[conflict],
  ),
  occurrencesBySlot: <String, List<ExternalSkillOccurrence>>{
    'one': occurrences,
  },
);

InspectedActivationOccupancy _occupancy(
  String targetPath, {
  required InspectedActivationContentRelation relation,
  String fingerprint = 'fingerprint',
  String? existingContentHash,
}) => InspectedActivationOccupancy(
  managedSkillId: ManagedSkillId('00000000-0000-4000-8000-000000000998'),
  slotKey: 'one',
  target: ResolvedActivationTarget(
    location: path.dirname(targetPath),
    scope: ActivationScope.global,
    mode: ActivationMode.copy,
    agentIds: const ['agent'],
  ),
  targetPath: targetPath,
  kind: InspectedActivationOccupancyKind.skillDirectory,
  contentRelation: relation,
  fingerprint: fingerprint,
  replaceable: true,
  existingContentHash: existingContentHash,
);

String _hash(String character) => List.filled(64, character).join();
