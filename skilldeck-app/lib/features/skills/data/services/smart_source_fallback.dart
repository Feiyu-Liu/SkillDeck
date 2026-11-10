import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// Smart web inputs try Git only when well-known discovery proves no Skills.
bool shouldTryWebSourceAsGit(WorkspaceFailure failure) =>
    switch (failure.code) {
      WorkspaceErrorCode.httpFailure =>
        failure.context['reason'] == 'unexpectedStatus',
      WorkspaceErrorCode.invalidSkill ||
      WorkspaceErrorCode.skillNotFound => true,
      _ => false,
    };
