import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import '../api/composite_command_dispatcher.dart';
import '../api/result.dart';
import '../api/revision_transfer.dart';
import '../api/skill_extra_data_patch.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/operations/workspace_business_changes.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../infrastructure/database/workspace_database.dart' as db;
import 'revision_transfer_command_handlers.dart';
import 'mutation_command_support.dart';

List<SkillsCommandHandler> buildSkillExtraDataPatchHandlers({
  required WorkspaceRevisionTransferCommands transfers,
  required OperationPlanAssembler plans,
}) =>
    [
      TypedSkillsCommandHandler<
        ReserveSkillExtraDataPatchRequest,
        IncomingRevisionCommandBinding
      >(
        kind: WorkspaceOperationKind.reserveSkillExtraDataPatch,
        handle:
            (request, context) async {
              final lease = await transfers.writerLock.acquire(
                waitPolicy: context.lockWaitPolicy,
              );
              try {
                final metadata = await transfers.database
                    .select(transfers.database.workspaceMetadata)
                    .getSingle();
                if (metadata.workspaceId !=
                        request.expectedIdentity.workspaceId ||
                    metadata.recoveryIncarnation !=
                        request.expectedIdentity.recoveryIncarnation ||
                    metadata.repositoryRevision !=
                        request.expectedRevision.value) {
                  return SkillsFailure(code: SkillsErrorCode.staleSnapshot);
                }
                final state = await transfers.states.readUpdateState(
                  request.managedSkillId,
                );
                if (state == null) {
                  return SkillsFailure(code: SkillsErrorCode.skillNotFound);
                }
                final previous =
                    await (transfers.database.select(
                          transfers.database.workspaceIncomingReservations,
                        )..where(
                          (row) => row.operationId.equals(
                            request.localOperationId.value,
                          ),
                        ))
                        .getSingleOrNull();
                final outcome =
                    await (transfers.database.select(
                          transfers.database.workspaceIncomingOutcomes,
                        )..where(
                          (row) => row.operationId.equals(
                            request.localOperationId.value,
                          ),
                        ))
                        .getSingleOrNull();
                final digest = _patchDigest(request.patch);
                final fingerprint = _fingerprint(
                  request.expectedIdentity,
                  request.managedSkillId,
                  state.sourceLineage.encoded,
                  digest,
                );
                if (previous != null || outcome != null) {
                  if ((previous?.requestFingerprint ??
                          outcome!.requestFingerprint) !=
                      fingerprint) {
                    return SkillsFailure(
                      code: SkillsErrorCode.operationFailed,
                      context: const {'reason': 'commandBindingMismatch'},
                    );
                  }
                } else {
                  if ((await (transfers.database.select(
                                transfers.database.operationJournals,
                              )..where(
                                (row) => row.operationId.equals(
                                  request.localOperationId.value,
                                ),
                              ))
                              .get())
                          .isNotEmpty ||
                      (await (transfers.database.select(
                                transfers.database.operationRecords,
                              )..where(
                                (row) => row.operationId.equals(
                                  request.localOperationId.value,
                                ),
                              ))
                              .get())
                          .isNotEmpty) {
                    return SkillsFailure(code: SkillsErrorCode.operationFailed);
                  }
                  await transfers.database
                      .into(transfers.database.workspaceIncomingReservations)
                      .insert(
                        db.WorkspaceIncomingReservationsCompanion.insert(
                          operationId: request.localOperationId.value,
                          requestFingerprint: fingerprint,
                          recoveryIncarnation: metadata.recoveryIncarnation,
                          managedSkillId: request.managedSkillId.value,
                          sourceLineageId: state.sourceLineage.encoded,
                          contentManifestDigest: digest,
                          newInstallation: false,
                        ),
                      );
                }
                return SkillsSuccess(
                  value: IncomingRevisionCommandBinding(
                    operationId: request.localOperationId,
                    requestFingerprint: fingerprint,
                    targetManagedSkillId: request.managedSkillId,
                    localLineageFingerprint: _lineage(
                      state.sourceLineage.encoded,
                    ),
                    expectedIdentity: request.expectedIdentity,
                  ),
                  changed: false,
                );
              } finally {
                await lease.release();
              }
            },
      ),
      TypedSkillsCommandHandler<
        ApplySkillExtraDataPatchRequest,
        IncomingRevisionApplyResult
      >(
        kind: WorkspaceOperationKind.applySkillExtraDataPatch,
        handle: (request, context) async {
          final binding = request.binding;
          final proof = await transfers.inspectOutcomeForBinding(
            binding,
            context,
          );
          if (proof.status == IncomingRevisionOutcomeStatus.applied) {
            final stored =
                await (transfers.database.select(
                      transfers.database.workspaceIncomingOutcomes,
                    )..where(
                      (row) =>
                          row.operationId.equals(binding.operationId.value),
                    ))
                    .getSingle();
            if (stored.contentManifestDigest != _patchDigest(request.patch)) {
              return SkillsFailure(
                code: SkillsErrorCode.operationFailed,
                context: const {'reason': 'commandBindingMismatch'},
              );
            }
            return SkillsSuccess(
              value: IncomingRevisionReplayed(proof),
              changed: false,
            );
          }
          if (proof.status == IncomingRevisionOutcomeStatus.rolledBack) {
            await transfers.operations.recover();
          }
          if (proof.status !=
                  IncomingRevisionOutcomeStatus.confirmedNotStarted &&
              proof.status != IncomingRevisionOutcomeStatus.rolledBack) {
            return SkillsSuccess(
              value: IncomingRevisionPending(
                IncomingRevisionPendingReason.stale,
              ),
              changed: false,
            );
          }
          final noChange = await transfers.completeKnownNoop(
            binding: binding,
            expectedRevision: request.expectedRevision,
            contentDigest: _patchDigest(request.patch),
            context: context,
            isSatisfied: (snapshot) async {
              final skill = snapshot.findSkill(binding.targetManagedSkillId);
              if (skill == null ||
                  request.patch.favorite != null &&
                      request.patch.favorite != skill.favorite.isFavorite ||
                  request.patch.noteChanged &&
                      request.patch.note != skill.note?.text) {
                return false;
              }
              final ids = {
                ...request.patch.addPersonalTagIds,
                ...request.patch.removePersonalTagIds,
              };
              if (ids.isNotEmpty &&
                  (await (transfers.database.select(
                        transfers.database.personalTags,
                      )..where((row) => row.id.isIn(ids))).get()).length !=
                      ids.length) {
                return false;
              }
              return request.patch.addPersonalTagIds.every(
                    skill.personalTagIds.contains,
                  ) &&
                  request.patch.removePersonalTagIds.every(
                    (id) => !skill.personalTagIds.contains(id),
                  );
            },
          );
          if (noChange) {
            return SkillsSuccess(
              value: IncomingRevisionReplayed(
                await transfers.inspectOutcomeForBinding(binding, context),
              ),
              changed: false,
            );
          }
          final result = await transfers.operations.execute(
            operationId: context.operationId,
            expectedRepositoryRevision: request.expectedRevision,
            lockWaitPolicy: context.lockWaitPolicy,
            cancellationToken: context.cancellationToken,
            buildPlan: (operation, revision) async {
              final metadata = await transfers.database
                  .select(transfers.database.workspaceMetadata)
                  .getSingle();
              if (metadata.workspaceId !=
                      binding.expectedIdentity.workspaceId ||
                  metadata.recoveryIncarnation !=
                      binding.expectedIdentity.recoveryIncarnation) {
                throw const ExternalOperationPreconditionChanged();
              }
              final reservation =
                  await (transfers.database.select(
                        transfers.database.workspaceIncomingReservations,
                      )..where(
                        (row) =>
                            row.operationId.equals(binding.operationId.value),
                      ))
                      .getSingle();
              final digest = _patchDigest(request.patch);
              if (digest != reservation.contentManifestDigest ||
                  _fingerprint(
                        binding.expectedIdentity,
                        binding.targetManagedSkillId,
                        reservation.sourceLineageId,
                        digest,
                      ) !=
                      binding.requestFingerprint ||
                  reservation.requestFingerprint !=
                      binding.requestFingerprint) {
                throw ArgumentError('Command binding mismatch.');
              }
              final current = await transfers.snapshots.reload();
              final skill = current.findSkill(binding.targetManagedSkillId);
              if (skill == null ||
                  _lineage(reservation.sourceLineageId) !=
                      binding.localLineageFingerprint) {
                throw const ExternalOperationPreconditionChanged();
              }
              final ids = {
                ...request.patch.addPersonalTagIds,
                ...request.patch.removePersonalTagIds,
              };
              if (ids.isNotEmpty &&
                  (await (transfers.database.select(
                        transfers.database.personalTags,
                      )..where((row) => row.id.isIn(ids))).get()).length !=
                      ids.length) {
                throw ArgumentError('Personal Tag unavailable.');
              }
              final now = DateTime.now().toUtc().microsecondsSinceEpoch;
              final favorite =
                  request.patch.favorite ?? skill.favorite.isFavorite;
              final favoriteChanged = favorite == skill.favorite.isFavorite
                  ? skill.favorite.changedAt?.microsecondsSinceEpoch
                  : favorite
                  ? now
                  : null;
              final note = request.patch.noteChanged
                  ? request.patch.note
                  : skill.note?.text;
              final noteChanged = note == skill.note?.text
                  ? skill.note?.updatedAt.microsecondsSinceEpoch
                  : note == null
                  ? null
                  : now;
              return plans.sqliteOnly(
                operationId: operation,
                expectedRepositoryRevision: revision,
                kind: WorkspaceOperationKind.applySkillExtraDataPatch,
                localCommandBinding: OperationLocalCommandBinding(
                  requestFingerprint: binding.requestFingerprint,
                  managedSkillId: skill.id,
                  sourceLineage: SourceLineageReference(
                    reservation.sourceLineageId,
                  ),
                ),
                businessChanges: WorkspaceBusinessChangeSet(
                  mutations: [
                    PutSkillUserData(
                      managedSkillId: skill.id,
                      favorite: favorite,
                      favoriteChangedAtMicros: favoriteChanged,
                      note: note,
                      noteUpdatedAtMicros: noteChanged,
                    ),
                    for (final tag in request.patch.addPersonalTagIds)
                      if (!skill.personalTagIds.contains(tag))
                        PutSkillTagAssignment(
                          managedSkillId: skill.id,
                          personalTagId: tag,
                          createdAtMicros: now,
                        ),
                    for (final tag in request.patch.removePersonalTagIds)
                      DeleteSkillTagAssignment(
                        managedSkillId: skill.id,
                        personalTagId: tag,
                      ),
                  ],
                ),
                subjects: [
                  OperationSubjectIntent(
                    managedSkillId: skill.id,
                    displayName: skill.displayName,
                    sourceLineage: SourceLineageReference(
                      reservation.sourceLineageId,
                    ),
                  ),
                ],
              );
            },
            onBusinessCommitted: context.markBusinessCommitted,
          );
          return mapMutationOutcome(
            outcome: result,
            context: context,
            snapshots: transfers.snapshots,
            valueFromSnapshot: (value) => IncomingRevisionApplied(
              MutationReport(
                snapshot: value,
                affectedSkillIds: {binding.targetManagedSkillId},
              ),
            ),
          );
        },
      ),
    ];
String _patchDigest(SkillExtraDataPatch patch) => sha256
    .convert(
      canonicalJson.encode({
        'favorite': patch.favorite,
        'noteChanged': patch.noteChanged,
        'note': patch.note,
        'add': patch.addPersonalTagIds.toList()..sort(),
        'remove': patch.removePersonalTagIds.toList()..sort(),
      }),
    )
    .toString();
String _fingerprint(
  WorkspaceIdentity identity,
  ManagedSkillId target,
  String lineage,
  String digest,
) => sha256
    .convert(
      canonicalJson.encode({
        'kind': 'applySkillExtraDataPatch',
        'workspaceId': identity.workspaceId,
        'incarnation': identity.recoveryIncarnation,
        'target': target.value,
        'lineage': lineage,
        'patchDigest': digest,
      }),
    )
    .toString();
String _lineage(String value) =>
    sha256.convert(utf8.encode('local-lineage:$value')).toString();
