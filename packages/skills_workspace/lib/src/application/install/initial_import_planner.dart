import 'package:path/path.dart' as path;

import '../../domain/activation_selection.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../../domain/source_descriptor.dart';
import '../activation/activation_models.dart';
import '../activation/activation_result.dart';
import '../activation/activation_target_resolver.dart';
import '../discovery/external_discovery_models.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../ports/agent_activation_ports.dart';
import '../ports/initial_import_ports.dart';
import '../source/source_acquisition_coordinator.dart';
import '../source/source_acquisition_models.dart';
import 'initial_import_models.dart';

/// Compiles initial Install and Adoption from one immutable Snapshot.
///
/// Every filesystem observation happens before the candidate port is called.
/// Expected failures therefore cannot leave a Store candidate, Repository Copy,
/// Activation, Journal row, or business row behind.
final class InitialImportPlanner {
  const InitialImportPlanner({
    required SourceAcquisitionCoordinator sourceAcquisition,
    required ActivationTargetResolver activationTargetResolver,
    ActivationTargetResolver Function()? activationTargetResolverFactory,
    required ActivationOccupancyProbePort occupancyProbe,
    required ActivationLocationIdentityPort locationIdentity,
    required WorkspaceEntityIdentityPort identities,
    required SourcePayloadEncodingPort sourcePayloads,
    required InitialRevisionCandidatePort revisionCandidates,
    required DateTime Function() clock,
  }) : _sourceAcquisition = sourceAcquisition,
       _activationTargetResolver = activationTargetResolver,
       _activationTargetResolverFactory = activationTargetResolverFactory,
       _occupancyProbe = occupancyProbe,
       _locationIdentity = locationIdentity,
       _identities = identities,
       _sourcePayloads = sourcePayloads,
       _revisionCandidates = revisionCandidates,
       _clock = clock;

  final SourceAcquisitionCoordinator _sourceAcquisition;
  final ActivationTargetResolver _activationTargetResolver;
  final ActivationTargetResolver Function()? _activationTargetResolverFactory;

  ActivationTargetResolver get _currentResolver =>
      _activationTargetResolverFactory?.call() ?? _activationTargetResolver;
  final ActivationOccupancyProbePort _occupancyProbe;
  final ActivationLocationIdentityPort _locationIdentity;
  final WorkspaceEntityIdentityPort _identities;
  final SourcePayloadEncodingPort _sourcePayloads;
  final InitialRevisionCandidatePort _revisionCandidates;
  final DateTime Function() _clock;

  Future<InitialImportPlanningResult<InitialImportPreflight>> planInstall({
    required RepositorySnapshot snapshot,
    required AcquiredSource acquiredSource,
    required ActivationSelection activationSelection,
    required RequestedActivationMode activationMode,
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
    CancellationToken? cancellationToken,
    Map<String, String>? confirmedTakeoverFingerprints,
    Map<String, String>? expectedTargetSignatures,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final early = _validateNewSlots<InitialImportPreflight>(
      snapshot,
      acquiredSource.skills,
      sourceWarnings: sourceWarnings,
    );
    if (early != null) return early;
    if (token.isCancelled) {
      return _cancelled(sourceWarnings: sourceWarnings);
    }
    final resolved = await _currentResolver.resolve(
      selection: activationSelection,
      requestedMode: activationMode,
      snapshot: snapshot,
    );
    final targets = resolved.valueOrNull;
    if (targets == null) {
      return _mapActivationFailure(
        resolved.failureOrNull!,
        sourceWarnings: sourceWarnings,
      );
    }
    final targetSignatures = _targetSignatures(targets);
    if (expectedTargetSignatures != null &&
        !_sameStrings(expectedTargetSignatures, targetSignatures)) {
      return InitialImportPlanningFailure<InitialImportPreflight>(
        code: InitialImportFailureCode.staleInstallTakeover,
        context: const <String, Object?>{'reason': 'activationTargetChanged'},
        sourceWarnings: sourceWarnings,
        activationWarnings: targets.warnings,
      );
    }
    final inputs = <_InitialImportInput>[
      for (final skill in acquiredSource.skills)
        _InitialImportInput(
          skill: skill,
          persistedSource: skill.provenance,
          targets: [
            for (final target in targets.targets)
              _ImportTarget(
                target: target,
                targetPath: path.join(target.location, skill.slotKey),
                mustExist: false,
              ),
          ],
        ),
    ];
    for (final input in inputs) {
      final collision = _findTargetCollision(input.targets);
      if (collision != null) {
        return _targetCollisionFailure(
          collision,
          slotKey: input.skill.slotKey,
          sourceWarnings: sourceWarnings,
          activationWarnings: targets.warnings,
        );
      }
    }
    return _preflight(
      kind: InitialImportKind.install,
      snapshot: snapshot,
      acquiredSource: acquiredSource,
      inputs: inputs,
      sourceWarnings: sourceWarnings,
      activationWarnings: targets.warnings,
      cancellationToken: token,
      confirmedTakeoverFingerprints: confirmedTakeoverFingerprints,
      targetSignatures: targetSignatures,
    );
  }

  Future<InitialImportPlanningResult<InitialImportPreflight>> planAdoption({
    required RepositorySnapshot snapshot,
    required ExternalAdoptionSelection selection,
    required ExternalSkillScan scan,
    RequestedActivationMode activationMode = RequestedActivationMode.automatic,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final existingFailure = _validateNewSlot<InitialImportPreflight>(
      snapshot,
      selection.slotKey,
    );
    if (existingFailure != null) return existingFailure;
    if (token.isCancelled) return _cancelled();

    final reviewed = _normalizedReviewedHashes(selection, _locationIdentity);
    if (reviewed == null) {
      return InitialImportPlanningFailure<InitialImportPreflight>(
        code: InitialImportFailureCode.staleExternalCandidate,
        context: <String, Object?>{
          'slotKey': selection.slotKey,
          'reason': 'reviewedLocationsAmbiguous',
        },
      );
    }
    final occurrences = scan.occurrencesBySlot[selection.slotKey];
    final current = occurrences == null
        ? null
        : _occurrencesByNormalizedLocation(occurrences, _locationIdentity);
    if (current == null || !_sameReviewedLocationHashes(reviewed, current)) {
      return InitialImportPlanningFailure<InitialImportPreflight>(
        code: InitialImportFailureCode.staleExternalCandidate,
        context: <String, Object?>{
          'slotKey': selection.slotKey,
          'reason': 'reviewedLocationsChanged',
        },
      );
    }
    final authoritativeKey = _locationIdentity.key(
      selection.authoritativeLocation,
    );
    final authoritative = current[authoritativeKey];
    final authoritativeHash = reviewed[authoritativeKey];
    if (authoritative == null || authoritativeHash == null) {
      return InitialImportPlanningFailure<InitialImportPreflight>(
        code: InitialImportFailureCode.staleExternalCandidate,
        context: <String, Object?>{
          'slotKey': selection.slotKey,
          'reason': 'authoritativeLocationNotDiscovered',
        },
      );
    }

    final reacquired = await _sourceAcquisition.acquire(
      source: authoritative.source,
      selectedSkillNames: const <String>{},
      options: const SourceAcquisitionOptions(),
      cancellationToken: token,
    );
    final source = reacquired.valueOrNull;
    if (source == null) {
      final failure = reacquired.failureOrNull!;
      return InitialImportPlanningFailure<InitialImportPreflight>(
        code: failure.code == SourceAcquisitionFailureCode.operationCancelled
            ? InitialImportFailureCode.operationCancelled
            : InitialImportFailureCode.sourceReacquisitionFailed,
        context: <String, Object?>{
          'slotKey': selection.slotKey,
          'sourceCode': failure.code.name,
        },
        sourceWarnings: failure.warnings,
      );
    }
    final skill = source.skills
        .where((item) => item.slotKey == selection.slotKey)
        .firstOrNull;
    if (skill == null || skill.tree.contentHash != authoritativeHash) {
      return InitialImportPlanningFailure<InitialImportPreflight>(
        code: InitialImportFailureCode.staleExternalCandidate,
        context: <String, Object?>{
          'slotKey': selection.slotKey,
          'reason': 'authoritativeContentChanged',
        },
        sourceWarnings: reacquired.warnings,
      );
    }
    final adoptedSource = AdoptedSnapshotSourceDescriptor(
      authoritativeLocation: _locationIdentity.normalize(
        authoritative.skillLocation,
      ),
      contentHash: skill.tree.contentHash,
    );
    final resolvedTargets = await _currentResolver.resolve(
      selection: _adoptionActivationSelection(current.values),
      requestedMode: activationMode,
      snapshot: snapshot,
    );
    final canonicalTargets = resolvedTargets.valueOrNull;
    if (canonicalTargets == null) {
      return _mapActivationFailure(
        resolvedTargets.failureOrNull!,
        sourceWarnings: reacquired.warnings,
      );
    }
    final importTargets = <_ImportTarget>[];
    final canonicalMutationKeys = <String>{};
    for (final target in canonicalTargets.targets) {
      final logicalTargetPath = path.join(target.location, skill.slotKey);
      var existing = current.values
          .where(
            (occurrence) =>
                _locationIdentity.key(occurrence.skillLocation) ==
                _locationIdentity.key(logicalTargetPath),
          )
          .firstOrNull;
      if (existing == null) {
        for (final occurrence in current.values) {
          if (await _locationIdentity.sameExistingObject(
            occurrence.skill.mutationPath,
            logicalTargetPath,
          )) {
            existing = occurrence;
            break;
          }
        }
      }
      final targetPath = existing?.skill.mutationPath ?? logicalTargetPath;
      if (existing != null) {
        canonicalMutationKeys.add(_locationIdentity.key(targetPath));
      }
      importTargets.add(
        _ImportTarget(
          target: target,
          targetPath: targetPath,
          mustExist: existing != null,
          reviewedContentHash: existing == null
              ? null
              : reviewed[_locationIdentity.key(existing.skillLocation)],
        ),
      );
    }
    final collision = _findTargetCollision(importTargets);
    if (collision != null) {
      return _targetCollisionFailure(
        collision,
        slotKey: skill.slotKey,
        sourceWarnings: reacquired.warnings,
        activationWarnings: canonicalTargets.warnings,
      );
    }
    final retirementsByPath = <String, _ImportRetirement>{};
    for (final occurrence in current.values) {
      final mutationKey = _locationIdentity.key(occurrence.skill.mutationPath);
      if (canonicalMutationKeys.contains(mutationKey)) continue;
      retirementsByPath.putIfAbsent(
        mutationKey,
        () => _ImportRetirement(
          target: occurrence.target.inspectionTarget,
          targetPath: occurrence.skill.mutationPath,
          reviewedContentHash:
              reviewed[_locationIdentity.key(occurrence.skillLocation)]!,
        ),
      );
    }
    return _preflight(
      kind: InitialImportKind.adoption,
      snapshot: snapshot,
      acquiredSource: AcquiredSource(
        canonicalSource: adoptedSource,
        skills: [skill],
      ),
      inputs: [
        _InitialImportInput(
          skill: skill,
          persistedSource: adoptedSource,
          targets: importTargets,
          retirements: retirementsByPath.values.toList(growable: false),
        ),
      ],
      sourceWarnings: reacquired.warnings,
      activationWarnings: canonicalTargets.warnings,
      cancellationToken: token,
    );
  }

  /// Two planned targets on one filesystem path would make the plan mutate
  /// that path twice. The resolver merges roots that are one physical
  /// directory, so this only remains as a typed guard in front of the plan
  /// builder's invariant.
  _TargetCollision? _findTargetCollision(List<_ImportTarget> targets) {
    final seen = <String, _ImportTarget>{};
    for (final target in targets) {
      final key = _locationIdentity.key(target.targetPath);
      final previous = seen[key];
      if (previous != null) {
        return _TargetCollision(first: previous, second: target);
      }
      seen[key] = target;
    }
    return null;
  }

  InitialImportPlanningFailure<InitialImportPreflight> _targetCollisionFailure(
    _TargetCollision collision, {
    required String slotKey,
    required List<SourceAcquisitionWarning> sourceWarnings,
    required List<ActivationWarning> activationWarnings,
  }) => InitialImportPlanningFailure<InitialImportPreflight>(
    code: InitialImportFailureCode.activationUnavailable,
    context: <String, Object?>{
      'reason': 'activationTargetsCollide',
      'slotKey': slotKey,
      'targetPath': collision.second.targetPath,
      'agentIds': <String>[
        ...collision.first.target.agentIds,
        ...collision.second.target.agentIds,
      ],
    },
    sourceWarnings: sourceWarnings,
    activationWarnings: activationWarnings,
  );

  Future<InitialImportPlanningResult<InitialImportPreflight>> _preflight({
    required InitialImportKind kind,
    required RepositorySnapshot snapshot,
    required AcquiredSource acquiredSource,
    required List<_InitialImportInput> inputs,
    required List<SourceAcquisitionWarning> sourceWarnings,
    required List<ActivationWarning> activationWarnings,
    required CancellationToken cancellationToken,
    Map<String, String>? confirmedTakeoverFingerprints,
    Map<String, String> targetSignatures = const <String, String>{},
  }) async {
    if (cancellationToken.isCancelled) {
      return _cancelled(
        sourceWarnings: sourceWarnings,
        activationWarnings: activationWarnings,
      );
    }
    final sorted = inputs.toList()
      ..sort(
        (left, right) => left.skill.slotKey.compareTo(right.skill.slotKey),
      );
    final subjects = <_PreparedSubject>[];
    final takeoverOccupancies = <InspectedActivationOccupancy>[];
    final now = _clock().toUtc();
    for (final input in sorted) {
      final encoded = _sourcePayloads.encode(input.persistedSource);
      if (encoded is! SourcePayloadEncoded) {
        return InitialImportPlanningFailure<InitialImportPreflight>(
          code: InitialImportFailureCode.sourcePayloadInvalid,
          context: <String, Object?>{'slotKey': input.skill.slotKey},
          sourceWarnings: sourceWarnings,
          activationWarnings: activationWarnings,
        );
      }
      subjects.add(
        _PreparedSubject(
          input: input,
          managedSkillId: _identities.allocateManagedSkillId(),
          sourceLineage: _identities.allocateSourceLineage(),
          sourcePayload: encoded.payload,
          observedFingerprints: <String, String>{},
        ),
      );
    }

    for (final subject in subjects) {
      final preview = _previewSkill(subject, now);
      for (final target in subject.input.targets) {
        if (cancellationToken.isCancelled) {
          return _cancelled(
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        final occupancy = await _occupancyProbe.inspect(
          skill: preview,
          target: target.target,
          targetPath: target.targetPath,
          cancellationToken: cancellationToken,
        );
        final failure = occupancy.failureOrNull;
        if (failure != null) {
          return _mapActivationFailure(
            failure,
            sourceWarnings: sourceWarnings,
            additionalWarnings: activationWarnings,
          );
        }
        final observed = occupancy.valueOrNull;
        if (!target.mustExist && observed != null) {
          if (!observed.replaceable && kind != InitialImportKind.adoption) {
            return InitialImportPlanningFailure<InitialImportPreflight>(
              code: InitialImportFailureCode.activationUnavailable,
              context: <String, Object?>{
                'slotKey': subject.input.skill.slotKey,
                'targetPath': target.targetPath,
                'reason': 'targetNotReplaceable',
              },
              sourceWarnings: sourceWarnings,
              activationWarnings: activationWarnings,
            );
          }
          final expected = confirmedTakeoverFingerprints?[target.targetPath];
          if (confirmedTakeoverFingerprints != null &&
              expected != observed.fingerprint) {
            return InitialImportPlanningFailure<InitialImportPreflight>(
              code: InitialImportFailureCode.staleInstallTakeover,
              context: <String, Object?>{
                'slotKey': subject.input.skill.slotKey,
                'targetPath': target.targetPath,
                'reason': 'activationTargetChanged',
              },
              sourceWarnings: sourceWarnings,
              activationWarnings: activationWarnings,
            );
          }
          subject.observedFingerprints[target.targetPath] =
              observed.fingerprint;
          takeoverOccupancies.add(observed);
        }
        if (!target.mustExist &&
            observed == null &&
            confirmedTakeoverFingerprints?.containsKey(target.targetPath) ==
                true) {
          return InitialImportPlanningFailure<InitialImportPreflight>(
            code: InitialImportFailureCode.staleInstallTakeover,
            context: <String, Object?>{
              'slotKey': subject.input.skill.slotKey,
              'targetPath': target.targetPath,
              'reason': 'activationTargetChanged',
            },
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        if (target.mustExist && observed == null) {
          return InitialImportPlanningFailure<InitialImportPreflight>(
            code: InitialImportFailureCode.staleExternalCandidate,
            context: <String, Object?>{
              'slotKey': subject.input.skill.slotKey,
              'targetPath': target.targetPath,
              'reason': 'externalTargetDisappeared',
            },
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        if (observed != null && target.mustExist) {
          if (!observed.replaceable) {
            return InitialImportPlanningFailure<InitialImportPreflight>(
              code: InitialImportFailureCode.activationUnavailable,
              context: <String, Object?>{
                'slotKey': subject.input.skill.slotKey,
                'targetPath': target.targetPath,
                'reason': 'targetNotReplaceable',
              },
              sourceWarnings: sourceWarnings,
              activationWarnings: activationWarnings,
            );
          }
          if (target.reviewedContentHash case final expectedHash?) {
            if (observed.existingContentHash != expectedHash) {
              return InitialImportPlanningFailure<InitialImportPreflight>(
                code: InitialImportFailureCode.staleExternalCandidate,
                context: <String, Object?>{
                  'slotKey': subject.input.skill.slotKey,
                  'targetPath': target.targetPath,
                  'reason': 'externalContentChanged',
                },
                sourceWarnings: sourceWarnings,
                activationWarnings: activationWarnings,
              );
            }
          } else if (observed.contentRelation !=
              InspectedActivationContentRelation.matchesCurrentRevision) {
            return InitialImportPlanningFailure<InitialImportPreflight>(
              code: InitialImportFailureCode.externalConflict,
              context: <String, Object?>{
                'slotKey': subject.input.skill.slotKey,
                'targetPath': target.targetPath,
                'reason': 'externalContentChanged',
              },
              sourceWarnings: sourceWarnings,
              activationWarnings: activationWarnings,
            );
          }
          subject.observedFingerprints[target.targetPath] =
              observed.fingerprint;
        }
      }
      for (final retirement in subject.input.retirements) {
        if (cancellationToken.isCancelled) {
          return _cancelled(
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        final occupancy = await _occupancyProbe.inspect(
          skill: preview,
          target: retirement.target,
          targetPath: retirement.targetPath,
          cancellationToken: cancellationToken,
        );
        final failure = occupancy.failureOrNull;
        if (failure != null) {
          return _mapActivationFailure(
            failure,
            sourceWarnings: sourceWarnings,
            additionalWarnings: activationWarnings,
          );
        }
        final observed = occupancy.valueOrNull;
        if (observed == null) {
          return InitialImportPlanningFailure<InitialImportPreflight>(
            code: InitialImportFailureCode.staleExternalCandidate,
            context: <String, Object?>{
              'slotKey': subject.input.skill.slotKey,
              'targetPath': retirement.targetPath,
              'reason': 'externalTargetDisappeared',
            },
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        if (!observed.replaceable) {
          return InitialImportPlanningFailure<InitialImportPreflight>(
            code: InitialImportFailureCode.activationUnavailable,
            context: <String, Object?>{
              'slotKey': subject.input.skill.slotKey,
              'targetPath': retirement.targetPath,
              'reason': 'targetNotReplaceable',
            },
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        if (observed.existingContentHash != retirement.reviewedContentHash) {
          return InitialImportPlanningFailure<InitialImportPreflight>(
            code: InitialImportFailureCode.staleExternalCandidate,
            context: <String, Object?>{
              'slotKey': subject.input.skill.slotKey,
              'targetPath': retirement.targetPath,
              'reason': 'externalContentChanged',
            },
            sourceWarnings: sourceWarnings,
            activationWarnings: activationWarnings,
          );
        }
        subject.observedFingerprints[retirement.targetPath] =
            observed.fingerprint;
      }
    }

    final revisionIntents = <InitialRevisionPreparationIntent>[
      for (final subject in subjects)
        InitialRevisionPreparationIntent(
          managedSkillId: subject.managedSkillId,
          sourceLineage: subject.sourceLineage,
          tree: subject.input.skill.tree,
          resolvedSourceRevision: acquiredSource.resolvedSourceRevision,
        ),
    ];
    final preflight = InitialImportPreflight(
      kind: kind,
      snapshotRevision: snapshot.revision,
      plannedAtMicros: now.microsecondsSinceEpoch,
      subjects: <InitialImportSubjectPreflight>[
        for (final subject in subjects)
          InitialImportSubjectPreflight(
            skill: subject.input.skill,
            managedSkillId: subject.managedSkillId,
            sourceLineage: subject.sourceLineage,
            sourcePayload: subject.sourcePayload,
            targets: <InitialImportTargetPreflight>[
              for (final target in subject.input.targets)
                InitialImportTargetPreflight(
                  target: target.target,
                  targetPath: target.targetPath,
                  mustExist:
                      target.mustExist ||
                      subject.observedFingerprints.containsKey(
                        target.targetPath,
                      ),
                  requiresInertOccupant:
                      kind == InitialImportKind.adoption &&
                      takeoverOccupancies.any(
                        (o) =>
                            o.targetPath == target.targetPath &&
                            o.adoptionOccupant.isInert,
                      ),
                  expectedExistingContentHash: target.reviewedContentHash,
                  expectedExistingFingerprint:
                      subject.observedFingerprints[target.targetPath],
                ),
            ],
            retirements: <InitialImportRetirementPreflight>[
              for (final retirement in subject.input.retirements)
                InitialImportRetirementPreflight(
                  target: retirement.target,
                  targetPath: retirement.targetPath,
                  expectedExistingContentHash: retirement.reviewedContentHash,
                  expectedExistingFingerprint:
                      subject.observedFingerprints[retirement.targetPath]!,
                ),
            ],
          ),
      ],
      revisionIntents: revisionIntents,
      sourceWarnings: sourceWarnings,
      activationWarnings: activationWarnings,
    );
    final blockers = kind == InitialImportKind.adoption
        ? takeoverOccupancies
              .where((o) => !o.replaceable || !o.adoptionOccupant.isInert)
              .toList()
        : takeoverOccupancies;
    blockers.sort((a, b) => a.targetPath.compareTo(b.targetPath));
    if (confirmedTakeoverFingerprints == null && blockers.isNotEmpty) {
      return InitialImportPlanningTakeoverRequired<InitialImportPreflight>(
        InitialImportTakeoverInspection(
          preflight: preflight,
          occupancies: blockers,
          targetSignatures: targetSignatures,
        ),
      );
    }
    return InitialImportPlanningSuccess<InitialImportPreflight>(preflight);
  }

  /// Performs the first candidate mutation only after [envelope] is durable,
  /// then compiles the candidate-dependent business plan without rereading the
  /// Source, Activation occupancy, or current Snapshot.
  Future<InitialImportPlanningResult<InitialImportPlan>> prepareAndAssemble({
    required InitialImportPreflight preflight,
    required PreparedOperationEnvelope envelope,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    if (envelope.expectedRepositoryRevision != preflight.snapshotRevision) {
      return InitialImportPlanningFailure<InitialImportPlan>(
        code: InitialImportFailureCode.revisionPreparationFailed,
        context: const <String, Object?>{'reason': 'envelopeRevisionMismatch'},
        sourceWarnings: preflight.sourceWarnings,
        activationWarnings: preflight.activationWarnings,
      );
    }
    if (token.isCancelled) {
      return _cancelled(
        sourceWarnings: preflight.sourceWarnings,
        activationWarnings: preflight.activationWarnings,
      );
    }
    final subjects = preflight.subjects;
    final revisionIntents = preflight.revisionIntents;
    final sourceWarnings = preflight.sourceWarnings;
    final activationWarnings = preflight.activationWarnings;
    final preparation = await _revisionCandidates.prepareInitialRevisions(
      revisionIntents,
      envelope: envelope,
      cancellationToken: token,
    );
    if (preparation is InitialRevisionPreparationFailure) {
      return InitialImportPlanningFailure<InitialImportPlan>(
        code:
            preparation.code ==
                InitialRevisionPreparationFailureCode.operationCancelled
            ? InitialImportFailureCode.operationCancelled
            : InitialImportFailureCode.revisionPreparationFailed,
        context: <String, Object?>{
          'revisionCode': preparation.code.name,
          if (preparation.detail case final detail?) 'detail': detail.name,
        },
        sourceWarnings: sourceWarnings,
        activationWarnings: activationWarnings,
      );
    }
    final prepared =
        (preparation as InitialRevisionPreparationSuccess).revisions;
    final envelopeReferences = envelope.preparationSteps
        .map((step) => step.recoveryReference)
        .toSet();
    final evidenceBySkill = <ManagedSkillId, PreparedInitialRevision>{};
    for (final item in prepared) {
      if (evidenceBySkill.containsKey(item.managedSkillId)) {
        return _invalidPreparedEvidence(
          'duplicateManagedSkill',
          sourceWarnings,
          activationWarnings,
        );
      }
      if (item.candidateRecoveryReference == item.bundleRecoveryReference ||
          !envelopeReferences.contains(item.candidateRecoveryReference) ||
          !envelopeReferences.contains(item.bundleRecoveryReference)) {
        return _invalidPreparedEvidence(
          'candidateRecoveryReferenceMismatch',
          sourceWarnings,
          activationWarnings,
        );
      }
      evidenceBySkill[item.managedSkillId] = item;
    }
    if (evidenceBySkill.length != subjects.length ||
        subjects.any(
          (subject) => !evidenceBySkill.containsKey(subject.managedSkillId),
        )) {
      return _invalidPreparedEvidence(
        'incompleteBatch',
        sourceWarnings,
        activationWarnings,
      );
    }

    final mutations = <WorkspaceBusinessMutation>[];
    final selectionChanges = <RevisionSelectionChangePlan>[];
    final recoveryIntents = <RevisionRecoveryIntent>[];
    final materializations = <InitialImportMaterializationIntent>[];
    for (final subject in subjects) {
      final evidence = evidenceBySkill[subject.managedSkillId]!;
      if (evidence.sourceLineage != subject.sourceLineage) {
        return _invalidPreparedEvidence(
          'candidateIdentityMismatch',
          sourceWarnings,
          activationWarnings,
        );
      }
      final skill = subject.skill;
      final address = RevisionAddress(
        sourceLineage: subject.sourceLineage,
        objectId: evidence.objectId,
      );
      final micros = preflight.plannedAtMicros;
      mutations.addAll(<WorkspaceBusinessMutation>[
        PutManagedSkill(
          managedSkillId: subject.managedSkillId,
          slotKey: skill.slotKey,
          declaredName: skill.declaredName,
          displayName: skill.declaredName,
          description: skill.description,
          activeSourceLineageId: subject.sourceLineage.encoded,
          createdAtMicros: micros,
          updatedAtMicros: micros,
        ),
        PutSourceLineage(
          sourceLineageId: subject.sourceLineage.encoded,
          managedSkillId: subject.managedSkillId,
          objectFormat: evidence.objectFormat,
          createdAtMicros: micros,
        ),
        PutSkillSource(
          sourceLineageId: subject.sourceLineage.encoded,
          kind: subject.sourcePayload.kind,
          payloadSchemaVersion: subject.sourcePayload.payloadSchemaVersion,
          payloadJson: subject.sourcePayload.payloadJson,
        ),
        PutRevisionMetadata(
          sourceLineageId: subject.sourceLineage.encoded,
          objectId: evidence.objectId.value,
          contentHash: skill.tree.contentHash,
          fileCount: skill.tree.fileCount,
          byteSize: skill.tree.byteSize,
          declaredName: skill.declaredName,
          validationState: WorkspaceRevisionValidationState.valid,
          validationCode: null,
          createdAtMicros: micros,
        ),
      ]);
      selectionChanges.add(
        RevisionSelectionChangePlan(
          managedSkillId: subject.managedSkillId,
          previousUpstream: null,
          previousEffective: null,
          intendedUpstream: address,
          intendedEffective: address,
        ),
      );
      recoveryIntents.add(
        RevisionRecoveryIntent(
          managedSkillId: subject.managedSkillId,
          sourceLineage: subject.sourceLineage,
          retainedRoot: evidence.objectId,
          recoveryReference: evidence.bundleRecoveryReference,
        ),
      );
      materializations.add(
        RepositoryCopyMaterializationIntent(
          managedSkillId: subject.managedSkillId,
          slotKey: skill.slotKey,
          revision: address,
        ),
      );
      for (final target in subject.targets) {
        mutations.add(
          PutActivation(
            activationId: _identities.allocateActivationId(),
            managedSkillId: subject.managedSkillId,
            canonicalPath: target.target.location,
            scope: _workspaceScope(target.target.scope),
            mode: _workspaceMode(target.target.mode),
            projectRootId: target.target.projectRootId,
            projectRootPath: target.target.projectRootPath,
            agentIds: target.target.agentIds,
            createdAtMicros: micros,
          ),
        );
        materializations.add(
          ActivationMaterializationIntent(
            managedSkillId: subject.managedSkillId,
            slotKey: skill.slotKey,
            revision: address,
            target: target.target,
            targetPath: target.targetPath,
            replaceExisting: target.mustExist,
            expectedExistingFingerprint: target.expectedExistingFingerprint,
          ),
        );
      }
      for (final retirement in subject.retirements) {
        materializations.add(
          ExternalOccurrenceRetirementIntent(
            managedSkillId: subject.managedSkillId,
            slotKey: skill.slotKey,
            revision: address,
            target: retirement.target,
            targetPath: retirement.targetPath,
            expectedExistingFingerprint: retirement.expectedExistingFingerprint,
          ),
        );
      }
    }
    return InitialImportPlanningSuccess<InitialImportPlan>(
      InitialImportPlan(
        kind: preflight.kind,
        businessChanges: WorkspaceBusinessChangeSet(mutations: mutations),
        revisionSelectionChanges: selectionChanges,
        revisionIntents: revisionIntents,
        preparedRevisions: prepared,
        recoveryIntents: recoveryIntents,
        materializationIntents: materializations,
        affectedSkillIds: preflight.affectedSkillIds,
        sourceWarnings: sourceWarnings,
        activationWarnings: activationWarnings,
      ),
    );
  }

  ManagedSkill _previewSkill(_PreparedSubject subject, DateTime now) =>
      ManagedSkill(
        id: subject.managedSkillId,
        createdAt: now,
        slotKey: subject.input.skill.slotKey,
        declaredName: subject.input.skill.declaredName,
        displayName: subject.input.skill.declaredName,
        description: subject.input.skill.description,
        source: subject.input.persistedSource,
        currentRevision: ManagedSkillRevisionSummary(
          contentHash: subject.input.skill.tree.contentHash,
          fileCount: subject.input.skill.tree.fileCount,
          byteSize: subject.input.skill.tree.byteSize,
          publishedAt: now,
        ),
      );
}

InitialImportPlanningFailure<T>? _validateNewSlots<T>(
  RepositorySnapshot snapshot,
  List<AcquiredSourceSkill> skills, {
  List<SourceAcquisitionWarning> sourceWarnings =
      const <SourceAcquisitionWarning>[],
}) {
  final seen = <String>{};
  for (final skill in skills) {
    if (!seen.add(skill.slotKey)) {
      return InitialImportPlanningFailure<T>(
        code: InitialImportFailureCode.duplicateSkillSlot,
        context: <String, Object?>{'slotKey': skill.slotKey},
        sourceWarnings: sourceWarnings,
      );
    }
    final failure = _validateNewSlot<T>(snapshot, skill.slotKey);
    if (failure != null) {
      return InitialImportPlanningFailure<T>(
        code: failure.code,
        context: failure.context,
        sourceWarnings: sourceWarnings,
      );
    }
  }
  if (skills.isEmpty) {
    return InitialImportPlanningFailure<T>(
      code: InitialImportFailureCode.staleExternalCandidate,
      context: const <String, Object?>{'reason': 'noSelectedSkills'},
      sourceWarnings: sourceWarnings,
    );
  }
  return null;
}

InitialImportPlanningFailure<T>? _validateNewSlot<T>(
  RepositorySnapshot snapshot,
  String slotKey,
) {
  final existing = snapshot.findSkillBySlotKey(slotKey);
  if (existing == null) return null;
  return InitialImportPlanningFailure<T>(
    code: existing.draft?.isDirty == true
        ? InitialImportFailureCode.dirtyDraftResolutionRequired
        : InitialImportFailureCode.sourceReplacementRequired,
    context: <String, Object?>{
      'slotKey': slotKey,
      'managedSkillId': existing.id.value,
    },
  );
}

InitialImportPlanningFailure<T> _cancelled<T>({
  List<SourceAcquisitionWarning> sourceWarnings =
      const <SourceAcquisitionWarning>[],
  List<ActivationWarning> activationWarnings = const <ActivationWarning>[],
}) => InitialImportPlanningFailure<T>(
  code: InitialImportFailureCode.operationCancelled,
  sourceWarnings: sourceWarnings,
  activationWarnings: activationWarnings,
);

InitialImportPlanningFailure<T> _mapActivationFailure<T>(
  ActivationFailure<Object?> failure, {
  required List<SourceAcquisitionWarning> sourceWarnings,
  List<ActivationWarning> additionalWarnings = const <ActivationWarning>[],
}) => InitialImportPlanningFailure<T>(
  code: switch (failure.code) {
    ActivationFailureCode.operationCancelled =>
      InitialImportFailureCode.operationCancelled,
    ActivationFailureCode.agentNotFound =>
      InitialImportFailureCode.agentNotFound,
    ActivationFailureCode.projectRootNotFound =>
      InitialImportFailureCode.projectRootNotFound,
    ActivationFailureCode.externalConflict =>
      InitialImportFailureCode.externalConflict,
    ActivationFailureCode.activationUnavailable =>
      InitialImportFailureCode.activationUnavailable,
    _ => InitialImportFailureCode.activationUnsupported,
  },
  context: failure.context,
  sourceWarnings: sourceWarnings,
  activationWarnings: <ActivationWarning>[
    ...additionalWarnings,
    ...failure.warnings,
  ],
);

InitialImportPlanningFailure<T> _invalidPreparedEvidence<T>(
  String reason,
  List<SourceAcquisitionWarning> sourceWarnings,
  List<ActivationWarning> activationWarnings,
) => InitialImportPlanningFailure<T>(
  code: InitialImportFailureCode.revisionPreparationFailed,
  context: <String, Object?>{'reason': reason},
  sourceWarnings: sourceWarnings,
  activationWarnings: activationWarnings,
);

WorkspaceActivationScope _workspaceScope(ActivationScope scope) =>
    switch (scope) {
      ActivationScope.global => WorkspaceActivationScope.global,
      ActivationScope.project => WorkspaceActivationScope.project,
    };

WorkspaceActivationMode _workspaceMode(ActivationMode mode) => switch (mode) {
  ActivationMode.copy => WorkspaceActivationMode.copy,
  ActivationMode.symbolicLink => WorkspaceActivationMode.symbolicLink,
};

final class _InitialImportInput {
  const _InitialImportInput({
    required this.skill,
    required this.persistedSource,
    required this.targets,
    this.retirements = const <_ImportRetirement>[],
  });

  final AcquiredSourceSkill skill;
  final SourceDescriptor persistedSource;
  final List<_ImportTarget> targets;
  final List<_ImportRetirement> retirements;
}

final class _ImportTarget {
  const _ImportTarget({
    required this.target,
    required this.targetPath,
    required this.mustExist,
    this.reviewedContentHash,
  });

  final ResolvedActivationTarget target;
  final String targetPath;
  final bool mustExist;
  final String? reviewedContentHash;
}

final class _ImportRetirement {
  const _ImportRetirement({
    required this.target,
    required this.targetPath,
    required this.reviewedContentHash,
  });

  final ResolvedActivationTarget target;
  final String targetPath;
  final String reviewedContentHash;
}

ActivationSelection _adoptionActivationSelection(
  Iterable<ExternalSkillOccurrence> occurrences,
) {
  final targets = <String, ActivationTarget>{};
  for (final occurrence in occurrences) {
    for (final target in occurrence.target.canonicalTargets) {
      for (final agentId in target.agentIds) {
        final key =
            '${target.scope.name}\u0000${target.projectRootId}\u0000$agentId';
        targets[key] = ActivationTarget(
          agentId: agentId,
          scope: target.scope,
          projectRootId: target.projectRootId,
        );
      }
    }
  }
  final entries = targets.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return ActivationSelection.explicit([
    for (final entry in entries) entry.value,
  ]);
}

Map<String, String>? _normalizedReviewedHashes(
  ExternalAdoptionSelection selection,
  ActivationLocationIdentityPort locationIdentity,
) {
  final normalized = <String, String>{};
  for (final entry in selection.reviewedContentHashByLocation.entries) {
    final locationKey = locationIdentity.key(entry.key);
    if (normalized.containsKey(locationKey)) return null;
    normalized[locationKey] = entry.value;
  }
  return normalized;
}

Map<String, ExternalSkillOccurrence>? _occurrencesByNormalizedLocation(
  List<ExternalSkillOccurrence> occurrences,
  ActivationLocationIdentityPort locationIdentity,
) {
  final byLocation = <String, ExternalSkillOccurrence>{};
  for (final occurrence in occurrences) {
    final locationKey = locationIdentity.key(occurrence.skillLocation);
    if (byLocation.containsKey(locationKey)) return null;
    byLocation[locationKey] = occurrence;
  }
  return byLocation;
}

Map<String, String> _targetSignatures(ResolvedActivationTargets targets) =>
    <String, String>{
      for (final target in targets.targets)
        target.location:
            '${target.scope.name}\u0000${target.mode.name}\u0000'
            '${target.projectRootId ?? ''}\u0000'
            '${target.projectRootPath ?? ''}\u0000'
            '${([...target.agentIds]..sort()).join('\u0001')}',
    };

bool _sameStrings(Map<String, String> left, Map<String, String> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

bool _sameReviewedLocationHashes(
  Map<String, String> reviewed,
  Map<String, ExternalSkillOccurrence> current,
) =>
    reviewed.length == current.length &&
    reviewed.entries.every(
      (entry) => current[entry.key]?.skill.contentHash == entry.value,
    );

final class _PreparedSubject {
  const _PreparedSubject({
    required this.input,
    required this.managedSkillId,
    required this.sourceLineage,
    required this.sourcePayload,
    required this.observedFingerprints,
  });

  final _InitialImportInput input;
  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final PersistedSourcePayload sourcePayload;
  final Map<String, String> observedFingerprints;
}

final class _TargetCollision {
  const _TargetCollision({required this.first, required this.second});

  final _ImportTarget first;
  final _ImportTarget second;
}
