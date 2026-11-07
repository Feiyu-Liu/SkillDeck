import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';

abstract interface class WorkspaceHistoryPort {
  Future<OperationHistoryPage> readOperationHistory({
    ManagedSkillId? managedSkillId,
    String? cursor,
    required int limit,
  });

  Future<PublishedHistoryPage> readPublishedHistory({
    required ManagedSkillId managedSkillId,
    String? cursor,
    required int limit,
  });
}
