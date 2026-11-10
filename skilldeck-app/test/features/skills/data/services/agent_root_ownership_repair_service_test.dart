import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/services/agent_root_ownership_repair_service.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  test('passes only reviewed paths as osascript arguments', () async {
    final runner = _RecordingRunner(output: 'ok\n');
    final service = MacOsAgentRootOwnershipRepairService(
      userHomePath: '/Users/tester',
      processRunner: runner,
      pathValidator: const _AllowPaths(),
      supported: true,
    );
    final audit = _audit(<String>[
      '/Users/tester/.zeta/skills',
      '/Users/tester/.alpha/skills',
    ]);

    final result = await service.repair(
      audit: audit,
      reviewedRootPaths: {
        '/Users/tester/.zeta/skills',
        '/Users/tester/.alpha/skills',
      },
    );

    expect(result, AgentRootOwnershipRepairOutcome.succeeded);
    expect(runner.executable, '/usr/bin/osascript');
    expect(runner.arguments[0], '-e');
    expect(runner.arguments[1], isA<String>());
    expect(runner.arguments[2], '--');
    expect(runner.arguments.skip(3), <String>[
      '501',
      '/Users/tester/.alpha/skills',
      '/Users/tester/.zeta/skills',
    ]);
    final script = runner.arguments[1];
    expect(script, contains('/usr/sbin/chown -R -P -x -n'));
    expect(script, contains('quoted form of'));
    expect(script, isNot(contains('/Users/tester/.alpha/skills')));
  });

  test('maps authorization cancellation without exposing stderr', () async {
    final service = MacOsAgentRootOwnershipRepairService(
      userHomePath: '/Users/tester',
      processRunner: _RecordingRunner(output: 'cancelled'),
      pathValidator: const _AllowPaths(),
      supported: true,
    );

    final result = await service.repair(
      audit: _audit(<String>['/Users/tester/.agent/skills']),
      reviewedRootPaths: {'/Users/tester/.agent/skills'},
    );

    expect(result, AgentRootOwnershipRepairOutcome.cancelled);
  });

  test('rejects unreviewed roots before starting a process', () async {
    final runner = _RecordingRunner(output: 'ok');
    final service = MacOsAgentRootOwnershipRepairService(
      userHomePath: '/Users/tester',
      processRunner: runner,
      pathValidator: const _AllowPaths(),
      supported: true,
    );

    final result = await service.repair(
      audit: _audit(<String>['/Users/tester/.agent/skills']),
      reviewedRootPaths: {'/Users/tester/.other/skills'},
    );

    expect(result, AgentRootOwnershipRepairOutcome.invalidReview);
    expect(runner.executable, isNull);
  });
}

WorkspaceAgentRootOwnershipAudit _audit(List<String> roots) =>
    WorkspaceAgentRootOwnershipAudit(
      supported: true,
      currentUserId: 501,
      examinedRootCount: roots.length,
      issues: [
        for (final root in roots)
          WorkspaceAgentRootOwnershipIssue(
            rootPath: root,
            agentIds: const {'agent'},
            roles: const {WorkspaceAgentSkillRootRole.canonicalActivation},
            reason: WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
            repairable: true,
          ),
      ],
    );

final class _RecordingRunner implements AgentRootOwnershipProcessRunner {
  _RecordingRunner({required this.output});

  final String output;
  String? executable;
  List<String> arguments = const [];

  @override
  Future<AgentRootOwnershipProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = List.unmodifiable(arguments);
    return AgentRootOwnershipProcessResult(exitCode: 0, standardOutput: output);
  }
}

final class _AllowPaths implements AgentRootOwnershipPathValidator {
  const _AllowPaths();

  @override
  Future<bool> isEligible({
    required String rootPath,
    required String userHome,
  }) async => true;
}
