import 'package:skills_workspace/skills_workspace.dart';

import 'destructive_sqlite_crash_harness.dart';

Future<void> main(List<String> arguments) async {
  if (arguments case [
    final workspace,
    final skillId,
    final effective,
    final boundary,
  ]) {
    final result = await runRemoteRemovalAtCommitBoundary(
      workspaceRoot: workspace,
      skillId: ManagedSkillId(skillId),
      expectedEffective: RevisionId(effective),
      exitAfterCommit: boundary == 'afterCommit',
    );
    throw StateError(
      'Remote Removal did not reach the Business Commit: $result',
    );
  }
  if (arguments.length != 2) {
    throw ArgumentError('Expected workspace root and crash point.');
  }
  await runDestructiveSqliteCrashChild(
    workspaceRoot: arguments[0],
    crashPoint: DestructiveSqliteCrashPoint.values.byName(arguments[1]),
  );
}
