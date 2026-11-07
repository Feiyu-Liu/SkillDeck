import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/composition/repository_command_composition.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

void main() {
  test('the business operation matrix excludes only lifecycle commands', () {
    final handlers = [
      for (final kind in WorkspaceOperationKind.values)
        if (kind != WorkspaceOperationKind.open &&
            kind != WorkspaceOperationKind.close)
          _Handler(kind),
    ];

    expect(() => assertCompleteBusinessHandlers(handlers), returnsNormally);
  });

  test('a missing handler is rejected before dispatcher construction', () {
    final handlers = [
      for (final kind in WorkspaceOperationKind.values)
        if (kind != WorkspaceOperationKind.open &&
            kind != WorkspaceOperationKind.close &&
            kind != WorkspaceOperationKind.remove)
          _Handler(kind),
    ];

    expect(
      () => assertCompleteBusinessHandlers(handlers),
      throwsA(isA<StateError>()),
    );
  });

  test('duplicate operation kinds are rejected', () {
    final handlers = [
      for (final kind in WorkspaceOperationKind.values)
        if (kind != WorkspaceOperationKind.open &&
            kind != WorkspaceOperationKind.close)
          _Handler(kind),
      _Handler(WorkspaceOperationKind.remove),
    ];

    expect(
      () => assertCompleteBusinessHandlers(handlers),
      throwsA(isA<StateError>()),
    );
  });

  for (final driftKind in [
    WorkspaceOperationKind.inspectSkillDrift,
    WorkspaceOperationKind.exportSkillDriftArtifact,
    WorkspaceOperationKind.resolveSkillDrift,
  ]) {
    test('${driftKind.name} must be present in business composition', () {
      final handlers = [
        for (final kind in WorkspaceOperationKind.values)
          if (kind != WorkspaceOperationKind.open &&
              kind != WorkspaceOperationKind.close &&
              kind != driftKind)
            _Handler(kind),
      ];

      expect(
        () => assertCompleteBusinessHandlers(handlers),
        throwsA(isA<StateError>()),
      );
    });
  }
}

final class _Handler implements SkillsCommandHandler {
  const _Handler(this.kind);

  @override
  final WorkspaceOperationKind kind;

  @override
  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  ) => throw UnimplementedError();
}
