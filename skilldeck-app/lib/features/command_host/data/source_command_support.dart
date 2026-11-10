import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_input_parser.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/data/services/smart_source_fallback.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'command_cancellation.dart';
import 'skill_selector_resolver.dart';

/// Uses the App's acquisition rules without exposing parser diagnostics.
({SkillSourceInput source, SkillSourceDetection detection}) parseSourceArgument(
  Object? raw, {
  String? ref,
}) {
  try {
    final input = raw as String;
    if (input.trim().isEmpty || ref != null && ref.trim().isEmpty) {
      throw const FormatException();
    }
    final parsed = SkillSourceInputParser().parse(
      input,
      mode: SkillSourceInputMode.smart,
    );
    final resolved = SkillSourceLocatorResolver().resolve(parsed.draft);
    return (
      source: SkillSourceInput(
        kind: switch (resolved.kind) {
          SkillSourceKind.local => WorkspaceSourceKind.local,
          SkillSourceKind.git => WorkspaceSourceKind.git,
          SkillSourceKind.wellKnown => WorkspaceSourceKind.wellKnown,
        },
        locator: resolved.value,
        ref: ref ?? resolved.ref,
        repositorySubpath: resolved.repositorySubpath,
      ),
      detection: parsed.detection,
    );
  } on SkillAcquisitionException {
    throw const SkillSelectionFailure('invalidSource');
  } on Object {
    throw const SkillSelectionFailure('usage');
  }
}

/// Inspection is cancellable and never counts as a committed write.
Future<WorkspaceSourceInspection> inspectSourceForCommand(
  SkillsWorkspaceRepository repository,
  SkillSourceInput source,
  SkillSourceDetection detection,
  CommandCancellation cancellation,
) async {
  try {
    var completion = await cancellation.complete(
      repository.inspectSource(source),
    );
    if (detection == SkillSourceDetection.webUrl &&
        completion is WorkspaceFailed<WorkspaceSourceInspection> &&
        shouldTryWebSourceAsGit(completion.failure) &&
        !cancellation.isCancelled) {
      completion = await cancellation.complete(
        repository.inspectSource(
          SkillSourceInput(
            kind: WorkspaceSourceKind.git,
            locator: source.locator,
            ref: source.ref,
            repositorySubpath: source.repositorySubpath,
            skillPath: source.skillPath,
          ),
        ),
      );
    }
    switch (completion) {
      case WorkspaceCompleted(:final value):
        return value;
      case WorkspaceFailed(:final failure):
        throw SkillSelectionFailure(
          cancellation.isCancelled ? 'operationCancelled' : failure.code.name,
        );
      case WorkspaceCommittedPending():
        throw const SkillSelectionFailure('operationFailed');
    }
  } on SkillSelectionFailure {
    rethrow;
  } on Object {
    throw const SkillSelectionFailure('operationFailed');
  }
}
