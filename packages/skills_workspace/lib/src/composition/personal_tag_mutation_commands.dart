import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../api/composite_command_dispatcher.dart';
import '../api/result.dart';
import '../api/personal_tag_mutation.dart';
import '../api/revision_transfer.dart';
import '../application/library/library_mutation_planner.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/workspace_business_changes.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../infrastructure/database/workspace_database.dart' as db;
import 'revision_transfer_command_handlers.dart';
import 'mutation_command_support.dart';

List<SkillsCommandHandler> buildPersonalTagMutationHandlers({
  required WorkspaceRevisionTransferCommands transfers,
  required OperationPlanAssembler plans,
}) {
  Future<PersonalTagMutationOutcome> inspect(
    PersonalTagCommandBinding binding,
    SkillsCommandContext context,
  ) async {
    final lease = await transfers.writerLock.acquire(
      waitPolicy: context.lockWaitPolicy,
    );
    try {
      final capture = (await transfers.captureUnderWriterLock(
        context,
      )).valueOrNull;
      if (capture == null || capture.identity != binding.expectedIdentity) {
        return PersonalTagMutationOutcome(
          status: PersonalTagMutationStatus.unknown,
          binding: binding,
          capture: capture,
        );
      }
      final outcome =
          await (transfers.database.select(
                transfers.database.workspaceGlobalCommandOutcomes,
              )..where(
                (row) => row.operationId.equals(binding.operationId.value),
              ))
              .getSingleOrNull();
      final reservation =
          await (transfers.database.select(
                transfers.database.workspaceGlobalCommandReservations,
              )..where(
                (row) => row.operationId.equals(binding.operationId.value),
              ))
              .getSingleOrNull();
      if (outcome != null &&
              (outcome.requestFingerprint != binding.requestFingerprint ||
                  outcome.personalTagId != binding.personalTagId) ||
          reservation != null &&
              (reservation.requestFingerprint != binding.requestFingerprint ||
                  reservation.personalTagId != binding.personalTagId)) {
        return PersonalTagMutationOutcome(
          status: PersonalTagMutationStatus.conflict,
          binding: binding,
          capture: capture,
        );
      }
      final journal =
          await (transfers.database.select(transfers.database.operationJournals)
                ..where(
                  (row) => row.operationId.equals(binding.operationId.value),
                ))
              .getSingleOrNull();
      final status = outcome != null
          ? journal == null && capture.isComplete
                ? PersonalTagMutationStatus.applied
                : PersonalTagMutationStatus.committedFinalizationPending
          : journal != null
          ? PersonalTagMutationStatus.inProgress
          : reservation != null && capture.isComplete
          ? PersonalTagMutationStatus.confirmedNotStarted
          : PersonalTagMutationStatus.unknown;
      return PersonalTagMutationOutcome(
        status: status,
        binding: binding,
        capture: capture,
        committedRevision: outcome == null
            ? null
            : RepositoryRevision(outcome.committedRepositoryRevision),
      );
    } finally {
      await lease.release();
    }
  }

  return [
    TypedSkillsCommandHandler<
      InspectPersonalTagMutationOutcomeRequest,
      PersonalTagMutationOutcome
    >(
      kind: WorkspaceOperationKind.inspectPersonalTagMutationOutcome,
      handle: (request, context) async => SkillsSuccess(
        value: await inspect(request.binding, context),
        changed: false,
      ),
    ),
    TypedSkillsCommandHandler<
      ReservePersonalTagMutationRequest,
      PersonalTagCommandBinding
    >(
      kind: WorkspaceOperationKind.reservePersonalTagMutation,
      handle: (request, context) async {
        final lease = await transfers.writerLock.acquire(
          waitPolicy: context.lockWaitPolicy,
        );
        try {
          final metadata = await transfers.database
              .select(transfers.database.workspaceMetadata)
              .getSingle();
          if (metadata.workspaceId != request.expectedIdentity.workspaceId ||
              metadata.recoveryIncarnation !=
                  request.expectedIdentity.recoveryIncarnation ||
              metadata.repositoryRevision != request.expectedRevision.value) {
            return SkillsFailure(code: SkillsErrorCode.staleSnapshot);
          }
          final reservation =
              await (transfers.database.select(
                    transfers.database.workspaceGlobalCommandReservations,
                  )..where(
                    (row) =>
                        row.operationId.equals(request.localOperationId.value),
                  ))
                  .getSingleOrNull();
          final outcome =
              await (transfers.database.select(
                    transfers.database.workspaceGlobalCommandOutcomes,
                  )..where(
                    (row) =>
                        row.operationId.equals(request.localOperationId.value),
                  ))
                  .getSingleOrNull();
          final tag =
              reservation?.personalTagId ??
              outcome?.personalTagId ??
              request.mutation.personalTagId ??
              const Uuid().v4();
          final fp = _fingerprint(
            request.expectedIdentity,
            tag,
            request.mutation,
          );
          if (reservation != null || outcome != null) {
            if ((reservation?.requestFingerprint ??
                    outcome!.requestFingerprint) !=
                fp) {
              return SkillsFailure(
                code: SkillsErrorCode.operationFailed,
                context: const {'reason': 'commandBindingMismatch'},
              );
            }
          } else {
            if ((await (transfers.database.select(
                  transfers.database.operationJournals,
                )..where((row) => row.operationId.equals(request.localOperationId.value))).get()).isNotEmpty ||
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
                .into(transfers.database.workspaceGlobalCommandReservations)
                .insert(
                  db.WorkspaceGlobalCommandReservationsCompanion.insert(
                    operationId: request.localOperationId.value,
                    requestFingerprint: fp,
                    recoveryIncarnation: metadata.recoveryIncarnation,
                    personalTagId: tag,
                  ),
                );
          }
          return SkillsSuccess(
            value: PersonalTagCommandBinding(
              operationId: request.localOperationId,
              requestFingerprint: fp,
              personalTagId: tag,
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
      ApplyPersonalTagMutationRequest,
      PersonalTagMutationOutcome
    >(
      kind: WorkspaceOperationKind.applyPersonalTagMutation,
      handle: (request, context) async {
        final binding = request.binding;
        if (request.mutation.kind != PersonalTagMutationKind.create &&
            request.mutation.personalTagId != binding.personalTagId) {
          return SkillsFailure(code: SkillsErrorCode.operationFailed);
        }
        if (_fingerprint(
              binding.expectedIdentity,
              binding.personalTagId,
              request.mutation,
            ) !=
            binding.requestFingerprint) {
          return SkillsFailure(
            code: SkillsErrorCode.operationFailed,
            context: const {'reason': 'commandBindingMismatch'},
          );
        }
        final prior = await inspect(binding, context);
        if (prior.status == PersonalTagMutationStatus.applied) {
          return SkillsSuccess(value: prior, changed: false);
        }
        if (prior.status == PersonalTagMutationStatus.rolledBack) {
          await transfers.operations.recover();
        }
        if (prior.status != PersonalTagMutationStatus.confirmedNotStarted &&
            prior.status != PersonalTagMutationStatus.rolledBack) {
          return SkillsSuccess(value: prior, changed: false);
        }
        LibraryPlanningResult<Object?> planTag(RepositorySnapshot snapshot) {
          final library = LibraryMutationPlanner(
            tagIds: () => binding.personalTagId,
          );
          final now = DateTime.now().toUtc();
          return switch (request.mutation.kind) {
            PersonalTagMutationKind.create => library.createTag(
              snapshot: snapshot,
              name: request.mutation.name!,
              color: request.mutation.color,
              createdAt: now,
            ),
            PersonalTagMutationKind.update => library.updateTag(
              snapshot: snapshot,
              tagId: binding.personalTagId,
              name: request.mutation.name!,
              color: request.mutation.color,
              updatedAt: now,
            ),
            PersonalTagMutationKind.delete => library.deleteTag(
              snapshot: snapshot,
              tagId: binding.personalTagId,
            ),
          };
        }

        final lease = await transfers.writerLock.acquire(
          waitPolicy: context.lockWaitPolicy,
        );
        var noChange = false;
        try {
          final captured = (await transfers.captureUnderWriterLock(
            context,
          )).valueOrNull;
          if (captured != null &&
              captured.isComplete &&
              captured.identity == binding.expectedIdentity &&
              captured.snapshot.revision == request.expectedRevision &&
              !context.cancellationToken.isCancelled) {
            noChange = await transfers.database.transaction(() async {
              final reservation =
                  await (transfers.database.select(
                        transfers.database.workspaceGlobalCommandReservations,
                      )..where(
                        (row) =>
                            row.operationId.equals(binding.operationId.value),
                      ))
                      .getSingleOrNull();
              if (reservation == null ||
                  reservation.requestFingerprint !=
                      binding.requestFingerprint ||
                  reservation.personalTagId != binding.personalTagId ||
                  reservation.recoveryIncarnation !=
                      binding.expectedIdentity.recoveryIncarnation ||
                  (await (transfers.database.select(
                            transfers.database.operationJournals,
                          )..where(
                            (row) => row.operationId.equals(
                              binding.operationId.value,
                            ),
                          ))
                          .get())
                      .isNotEmpty) {
                return false;
              }
              final planned = planTag(captured.snapshot);
              if (planned is! LibraryMutationPlan || planned.changed) {
                return false;
              }
              await transfers.database
                  .into(transfers.database.workspaceGlobalCommandOutcomes)
                  .insert(
                    db.WorkspaceGlobalCommandOutcomesCompanion.insert(
                      operationId: binding.operationId.value,
                      requestFingerprint: binding.requestFingerprint,
                      personalTagId: binding.personalTagId,
                      committedRepositoryRevision:
                          request.expectedRevision.value,
                    ),
                  );
              await (transfers.database.delete(
                    transfers.database.workspaceGlobalCommandReservations,
                  )..where(
                    (row) => row.operationId.equals(binding.operationId.value),
                  ))
                  .go();
              return true;
            });
          }
        } finally {
          await lease.release();
        }
        if (noChange) {
          context.markBusinessCommitted();
          return SkillsSuccess(
            value: await inspect(binding, context),
            changed: false,
          );
        }
        LibraryPlanningFailureCode? planningFailure;
        final result = await transfers.operations.execute(
          operationId: context.operationId,
          expectedRepositoryRevision: request.expectedRevision,
          lockWaitPolicy: context.lockWaitPolicy,
          cancellationToken: context.cancellationToken,
          buildPlan: (operation, revision) async {
            final metadata = await transfers.database
                .select(transfers.database.workspaceMetadata)
                .getSingle();
            if (metadata.workspaceId != binding.expectedIdentity.workspaceId ||
                metadata.recoveryIncarnation !=
                    binding.expectedIdentity.recoveryIncarnation) {
              throw const ExternalOperationPreconditionChanged();
            }
            final snapshot = await transfers.snapshots.reload();
            final planned = planTag(snapshot);
            if (planned is LibraryPlanningFailure) {
              planningFailure = planned.code;
              throw ArgumentError('Personal Tag conflict.');
            }
            final mutations =
                (planned as LibraryMutationPlan).changes.mutations;
            return plans.sqliteOnly(
              operationId: operation,
              expectedRepositoryRevision: revision,
              kind: WorkspaceOperationKind.applyPersonalTagMutation,
              retainWithoutSubjects: true,
              businessChanges: WorkspaceBusinessChangeSet(
                mutations: [
                  ...mutations,
                  PutGlobalCommandOutcome(
                    operationId: binding.operationId,
                    requestFingerprint: binding.requestFingerprint,
                    personalTagId: binding.personalTagId,
                    committedRepositoryRevision: revision.next(),
                  ),
                ],
              ),
            );
          },
          onBusinessCommitted: context.markBusinessCommitted,
        );
        if (result is OperationRejected && planningFailure != null) {
          return SkillsSuccess(
            value: PersonalTagMutationOutcome(
              status:
                  planningFailure ==
                      LibraryPlanningFailureCode.duplicatePersonalTag
                  ? PersonalTagMutationStatus.nameConflict
                  : PersonalTagMutationStatus.tagNotFound,
              binding: binding,
            ),
            changed: false,
          );
        }
        return mapMutationOutcome(
          outcome: result,
          context: context,
          snapshots: transfers.snapshots,
          valueFromSnapshot: (_) => PersonalTagMutationOutcome(
            status: PersonalTagMutationStatus.applied,
            binding: binding,
            committedRevision: request.expectedRevision.next(),
          ),
        );
      },
    ),
  ];
}

String _fingerprint(
  WorkspaceIdentity identity,
  String tag,
  PersonalTagMutation mutation,
) => sha256
    .convert(
      canonicalJson.encode({
        'kind': 'personalTagMutation',
        'workspaceId': identity.workspaceId,
        'incarnation': identity.recoveryIncarnation,
        'tag': tag,
        'mutation': mutation.kind.name,
        'name': mutation.name,
        'color': mutation.color,
      }),
    )
    .toString();
