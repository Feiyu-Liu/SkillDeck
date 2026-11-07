import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  final operationId = OperationId('123e4567-e89b-42d3-a456-426614174000');
  final warning = SkillsWarning(
    code: SkillsWarningCode.finalizationDeferred,
    context: const {'operation': 'remove'},
  );

  test('SkillsResult exposes three disjoint terminal states', () {
    final success = SkillsSuccess<String>(
      value: 'complete',
      changed: true,
      warnings: [warning],
    );
    final failure = SkillsFailure<String>(
      code: SkillsErrorCode.draftChangedDuringPublish,
      context: const {'attempts': 3},
      diagnostic: 'redacted',
      warnings: [warning],
    );
    final pending = SkillsCommittedFinalizationPending<String>(
      operationId: operationId,
      committedRepositoryRevision: RepositoryRevision(9),
      warnings: [warning],
    );

    expect(
      (
        success.isSuccess,
        success.isFailure,
        success.isCommittedFinalizationPending,
      ),
      (true, false, false),
    );
    expect(
      (
        failure.isSuccess,
        failure.isFailure,
        failure.isCommittedFinalizationPending,
      ),
      (false, true, false),
    );
    expect(
      (
        pending.isSuccess,
        pending.isFailure,
        pending.isCommittedFinalizationPending,
      ),
      (false, false, true),
    );
    expect(success.valueOrNull, 'complete');
    expect(failure.failureOrNull, same(failure));
    expect(pending.finalizationPendingOrNull, same(pending));
  });

  test('fold exhaustively handles committed finalization pending', () {
    final results = <SkillsResult<String>>[
      SkillsSuccess<String>(value: 'complete'),
      SkillsFailure<String>(code: SkillsErrorCode.operationFailed),
      SkillsCommittedFinalizationPending<String>(
        operationId: operationId,
        committedRepositoryRevision: RepositoryRevision(9),
      ),
    ];

    expect(
      results.map(
        (result) => result.fold(
          onSuccess: (_) => 'success',
          onFailure: (_) => 'failure',
          onCommittedFinalizationPending: (_) => 'pending',
        ),
      ),
      ['success', 'failure', 'pending'],
    );
  });

  test('result collections are immutable and equality is value based', () {
    final context = <String, Object?>{'operation': 'publish'};
    final warnings = <SkillsWarning>[warning];
    final failure = SkillsFailure<void>(
      code: SkillsErrorCode.declaredNameChangeNotAllowed,
      context: context,
      warnings: warnings,
    );
    context['late'] = true;
    warnings.clear();

    expect(failure.context, {'operation': 'publish'});
    expect(failure.warnings, [warning]);
    expect(() => failure.context['extra'] = true, throwsUnsupportedError);
    expect(() => failure.warnings.clear(), throwsUnsupportedError);
    expect(
      failure,
      SkillsFailure<void>(
        code: SkillsErrorCode.declaredNameChangeNotAllowed,
        context: const {'operation': 'publish'},
        warnings: [
          SkillsWarning(
            code: SkillsWarningCode.finalizationDeferred,
            context: const {'operation': 'remove'},
          ),
        ],
      ),
    );
  });

  test('committed pending contains only stable public recovery references', () {
    final result = SkillsCommittedFinalizationPending<String>(
      operationId: operationId,
      committedRepositoryRevision: RepositoryRevision(11),
      warnings: [warning],
    );

    expect(result.operationId, operationId);
    expect(result.committedRepositoryRevision, RepositoryRevision(11));
    expect(result.valueOrNull, isNull);
    expect(result.failureOrNull, isNull);
  });

  test('warning value semantics are stable and detached from caller maps', () {
    final mutableContext = <String, Object?>{'slotKey': 'reviewer'};
    final first = SkillsWarning(
      code: SkillsWarningCode.activationTargetSkipped,
      context: mutableContext,
    );
    mutableContext['slotKey'] = 'changed';
    final equal = SkillsWarning(
      code: SkillsWarningCode.activationTargetSkipped,
      context: const {'slotKey': 'reviewer'},
    );

    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(first, isNot(warning));
    expect(first.context, {'slotKey': 'reviewer'});
    expect(() => first.context.clear(), throwsUnsupportedError);
    expect(
      first.toString(),
      contains('SkillsWarning(code: SkillsWarningCode.activationTargetSkipped'),
    );
  });

  test('success has complete immutable value semantics', () {
    final mutableWarnings = <SkillsWarning>[warning];
    final first = SkillsSuccess<String>(
      value: 'complete',
      changed: true,
      warnings: mutableWarnings,
    );
    mutableWarnings.clear();
    final equal = SkillsSuccess<String>(
      value: 'complete',
      changed: true,
      warnings: [warning],
    );

    expect(first.failureOrNull, isNull);
    expect(first.finalizationPendingOrNull, isNull);
    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(first, isNot(SkillsSuccess<String>(value: 'different')));
    expect(() => first.warnings.clear(), throwsUnsupportedError);
    expect(first.toString(), contains('SkillsSuccess(value: complete'));
  });

  test('failure exposes only failure data with stable value semantics', () {
    final first = SkillsFailure<String>(
      code: SkillsErrorCode.invalidSkill,
      context: const {'reason': 'frontmatter'},
      diagnostic: 'redacted',
      warnings: [warning],
    );
    final equal = SkillsFailure<String>(
      code: SkillsErrorCode.invalidSkill,
      context: const {'reason': 'frontmatter'},
      diagnostic: 'redacted',
      warnings: [warning],
    );

    expect(first.valueOrNull, isNull);
    expect(first.finalizationPendingOrNull, isNull);
    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(
      first,
      isNot(
        SkillsFailure<String>(
          code: SkillsErrorCode.invalidSkill,
          diagnostic: 'different',
        ),
      ),
    );
    expect(first.toString(), contains('diagnostic: redacted'));
  });

  test('committed-pending has immutable warnings and value semantics', () {
    final mutableWarnings = <SkillsWarning>[warning];
    final first = SkillsCommittedFinalizationPending<String>(
      operationId: operationId,
      committedRepositoryRevision: RepositoryRevision(9),
      warnings: mutableWarnings,
    );
    mutableWarnings.clear();
    final equal = SkillsCommittedFinalizationPending<String>(
      operationId: operationId,
      committedRepositoryRevision: RepositoryRevision(9),
      warnings: [warning],
    );

    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(
      first,
      isNot(
        SkillsCommittedFinalizationPending<String>(
          operationId: operationId,
          committedRepositoryRevision: RepositoryRevision(10),
        ),
      ),
    );
    expect(() => first.warnings.clear(), throwsUnsupportedError);
    expect(
      first.toString(),
      contains('SkillsCommittedFinalizationPending(operationId:'),
    );
  });
}
