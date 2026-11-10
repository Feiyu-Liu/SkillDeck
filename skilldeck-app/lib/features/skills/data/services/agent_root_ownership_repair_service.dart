import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

enum AgentRootOwnershipRepairOutcome {
  succeeded,
  cancelled,
  rejected,
  failed,
  unsupported,
  invalidReview,
}

abstract interface class AgentRootOwnershipRepairService {
  Future<AgentRootOwnershipRepairOutcome> repair({
    required WorkspaceAgentRootOwnershipAudit audit,
    required Set<String> reviewedRootPaths,
  });
}

abstract interface class AgentRootOwnershipProcessRunner {
  Future<AgentRootOwnershipProcessResult> run(
    String executable,
    List<String> arguments,
  );
}

final class AgentRootOwnershipProcessResult {
  const AgentRootOwnershipProcessResult({
    required this.exitCode,
    required this.standardOutput,
  });

  final int exitCode;
  final String standardOutput;
}

abstract interface class AgentRootOwnershipPathValidator {
  Future<bool> isEligible({required String rootPath, required String userHome});
}

final class MacOsAgentRootOwnershipRepairService
    implements AgentRootOwnershipRepairService {
  MacOsAgentRootOwnershipRepairService({
    required String userHomePath,
    AgentRootOwnershipProcessRunner? processRunner,
    AgentRootOwnershipPathValidator? pathValidator,
    bool? supported,
  }) : _userHomePath = path.normalize(path.absolute(userHomePath)),
       _processRunner = processRunner ?? const _DirectProcessRunner(),
       _pathValidator = pathValidator ?? const _FileSystemPathValidator(),
       _supported = supported ?? Platform.isMacOS;

  final String _userHomePath;
  final AgentRootOwnershipProcessRunner _processRunner;
  final AgentRootOwnershipPathValidator _pathValidator;
  final bool _supported;

  @override
  Future<AgentRootOwnershipRepairOutcome> repair({
    required WorkspaceAgentRootOwnershipAudit audit,
    required Set<String> reviewedRootPaths,
  }) async {
    if (!_supported) return AgentRootOwnershipRepairOutcome.unsupported;
    final userId = audit.currentUserId;
    if (!audit.supported || userId == null || userId < 0) {
      return AgentRootOwnershipRepairOutcome.invalidReview;
    }

    final repairableByPath = <String, WorkspaceAgentRootOwnershipIssue>{
      for (final issue in audit.repairableIssues) issue.rootPath: issue,
    };
    final roots = reviewedRootPaths.toList()..sort();
    if (roots.isEmpty ||
        roots.length != reviewedRootPaths.length ||
        roots.any((root) => repairableByPath[root] == null)) {
      return AgentRootOwnershipRepairOutcome.invalidReview;
    }
    for (final root in roots) {
      if (!await _pathValidator.isEligible(
        rootPath: root,
        userHome: _userHomePath,
      )) {
        return AgentRootOwnershipRepairOutcome.invalidReview;
      }
    }

    try {
      final result = await _processRunner.run('/usr/bin/osascript', <String>[
        '-e',
        _ownershipRepairAppleScript,
        '--',
        '$userId',
        ...roots,
      ]);
      if (result.exitCode != 0) {
        return AgentRootOwnershipRepairOutcome.failed;
      }
      return switch (result.standardOutput.trim()) {
        'ok' => AgentRootOwnershipRepairOutcome.succeeded,
        'cancelled' => AgentRootOwnershipRepairOutcome.cancelled,
        'rejected' => AgentRootOwnershipRepairOutcome.rejected,
        _ => AgentRootOwnershipRepairOutcome.failed,
      };
    } on ProcessException {
      return AgentRootOwnershipRepairOutcome.failed;
    }
  }
}

const String _ownershipRepairAppleScript = r'''
on run argv
  if (count of argv) < 2 then return "invalid"
  set userId to item 1 of argv
  set commandText to "/usr/sbin/chown -R -P -x -n " & quoted form of userId
  repeat with itemIndex from 2 to (count of argv)
    set commandText to commandText & " " & quoted form of (item itemIndex of argv)
  end repeat
  try
    do shell script commandText with administrator privileges
    return "ok"
  on error errorMessage number errorNumber
    if errorNumber is -128 or errorNumber is -60006 then return "cancelled"
    if errorNumber is -60005 or errorNumber is -60007 then return "rejected"
    return "failed"
  end try
end run
''';

final class _DirectProcessRunner implements AgentRootOwnershipProcessRunner {
  const _DirectProcessRunner();

  @override
  Future<AgentRootOwnershipProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return AgentRootOwnershipProcessResult(
      exitCode: result.exitCode,
      standardOutput: '${result.stdout}',
    );
  }
}

final class _FileSystemPathValidator
    implements AgentRootOwnershipPathValidator {
  const _FileSystemPathValidator();

  @override
  Future<bool> isEligible({
    required String rootPath,
    required String userHome,
  }) async {
    final normalizedRoot = path.normalize(path.absolute(rootPath));
    final type = await FileSystemEntity.type(
      normalizedRoot,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory) return false;
    try {
      final physicalHome = path.normalize(
        await Directory(userHome).resolveSymbolicLinks(),
      );
      final physicalRoot = path.normalize(
        await Directory(normalizedRoot).resolveSymbolicLinks(),
      );
      return physicalRoot == normalizedRoot &&
          path.isWithin(physicalHome, physicalRoot);
    } on FileSystemException {
      return false;
    }
  }
}
