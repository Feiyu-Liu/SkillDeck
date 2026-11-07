import 'package:path/path.dart' as path;

import '../domain/lock_wait_policy.dart';
import '../domain/public_models.dart';

/// Immutable configuration used to construct one local [SkillsRepository].
///
/// Authentication material is deliberately absent. External Git credentials
/// remain owned by the user's system Git credential flow, and future HTTP auth
/// is supplied by an outer transport adapter rather than persisted here.
final class SkillsRepositoryConfiguration {
  SkillsRepositoryConfiguration({
    required String rootPath,
    this.defaultLockWaitPolicy = const LockWaitPolicy.failFast(),
    List<AgentDefinition> additionalAgents = const [],
    String? agentHomePath,
  }) : rootPath = _absolute(rootPath, 'rootPath'),
       agentHomePath = agentHomePath == null
           ? null
           : _absolute(agentHomePath, 'agentHomePath'),
       additionalAgents = List.unmodifiable(additionalAgents) {
    final ids = <String>{};
    for (final agent in this.additionalAgents) {
      if (!ids.add(agent.id)) {
        throw ArgumentError.value(
          agent.id,
          'additionalAgents',
          'contains a duplicate Agent ID',
        );
      }
    }
  }

  final String rootPath;
  final LockWaitPolicy defaultLockWaitPolicy;
  final String? agentHomePath;
  final List<AgentDefinition> additionalAgents;
}

String _absolute(String value, String name) {
  if (!path.isAbsolute(value) || path.isRootRelative(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a fully qualified absolute path',
    );
  }
  return path.normalize(value);
}
