import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

enum SkillSourceKind { local, git, wellKnown }

enum SkillSourceInputMode { smart, typed }

enum SkillSourceDetection {
  empty,
  local,
  gitShorthand,
  gitHostedUrl,
  gitRemote,
  webUrl,
}

enum AcquisitionStep { source, skills, activation }

enum SkillActivationScope { global, project }

enum SkillAcquisitionOperation {
  resolveSource,
  inspectSource,
  installSkills,
  confirmInstallTakeover,
  refreshAfterInstall,
}

enum SkillAcquisitionErrorCode {
  emptyLocator,
  invalidLocalLocator,
  invalidFileLocator,
  inspectFailed,
  webSourceHasNoSkills,
  installFailed,
  refreshFailed,
  unexpected,
}

final class SkillAcquisitionException implements AppFailure {
  const SkillAcquisitionException({
    required this.operation,
    required this.code,
    this.context = const {},
  });

  final SkillAcquisitionOperation operation;
  final SkillAcquisitionErrorCode code;

  @override
  String get codeKey => code.name;

  @override
  String get operationKey => operation.name;

  @override
  AppFailureMessage get message => switch (operation) {
    SkillAcquisitionOperation.resolveSource =>
      AppFailureMessage.invalidSourceInput,
    SkillAcquisitionOperation.inspectSource => AppFailureMessage.inspectSource,
    SkillAcquisitionOperation.installSkills => AppFailureMessage.installSkills,
    SkillAcquisitionOperation.confirmInstallTakeover =>
      AppFailureMessage.installSkills,
    SkillAcquisitionOperation.refreshAfterInstall =>
      AppFailureMessage.refreshAfterInstall,
  };

  @override
  AppRecoveryPolicy get recoveryPolicy => switch (code) {
    SkillAcquisitionErrorCode.webSourceHasNoSkills => AppRecoveryPolicy.none,
    _ => AppRecoveryPolicy.retryExplicitly,
  };

  @override
  final Map<String, Object?> context;

  @override
  String? get diagnostic => null;

  @override
  Iterable<AppWarning> get warnings => const [];

  @override
  String toString() => 'SkillAcquisitionException($operation, ${code.name})';
}

final class SkillSourceDraft {
  const SkillSourceDraft({
    this.kind = SkillSourceKind.git,
    this.locator = '',
    this.sourceRef = '',
    this.repositorySubpath = '',
  });

  final SkillSourceKind kind;
  final String locator;
  final String sourceRef;
  final String repositorySubpath;

  SkillSourceDraft copyWith({
    SkillSourceKind? kind,
    String? locator,
    String? sourceRef,
    String? repositorySubpath,
  }) => SkillSourceDraft(
    kind: kind ?? this.kind,
    locator: locator ?? this.locator,
    sourceRef: sourceRef ?? this.sourceRef,
    repositorySubpath: repositorySubpath ?? this.repositorySubpath,
  );
}

final class ResolvedSkillSource {
  const ResolvedSkillSource({
    required this.kind,
    required this.value,
    this.ref,
    this.repositorySubpath = '',
  });

  final SkillSourceKind kind;
  final String value;
  final String? ref;
  final String repositorySubpath;
}

final class SkillCandidate {
  const SkillCandidate({
    required this.slotKey,
    required this.declaredName,
    required this.description,
    required this.skillPath,
    this.contentHash = '',
    this.fileCount = 0,
    this.byteSize = 0,
  });

  final String slotKey;
  final String declaredName;
  final String description;
  final String skillPath;
  final String contentHash;
  final int fileCount;
  final int byteSize;
}

final class AgentOption {
  const AgentOption({
    required this.id,
    required this.displayName,
    this.detected = true,
    this.location = '',
    this.iconName = 'bot',
  });

  final String id;
  final String displayName;
  final bool detected;
  final String location;
  final String iconName;
}

final class SkillSourceInspection {
  SkillSourceInspection({
    required this.source,
    required List<SkillCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);

  final ResolvedSkillSource source;
  final List<SkillCandidate> candidates;
}

enum AcquisitionPhase {
  preparing,
  inspecting,
  waitingForLock,
  planning,
  applying,
  rollingBack,
  completed,
}

final class AcquisitionProgress {
  const AcquisitionProgress({
    required this.phase,
    this.currentItem,
    this.completed = 0,
    this.total,
    this.warnings = const [],
  });

  final AcquisitionPhase phase;
  final String? currentItem;
  final int completed;
  final int? total;
  final List<WorkspaceWarning> warnings;

  double? get fraction =>
      total == null || total == 0 ? null : completed / total!;
}

final class InstallSelection {
  InstallSelection({
    required this.source,
    required Set<String> selectedSkillNames,
    required Set<String> selectedAgentIds,
    required this.installAllSkills,
    this.scope = SkillActivationScope.global,
    this.projectRootId,
    this.storeOnly = false,
    this.activationMethod = WorkspaceActivationMethod.automatic,
  }) : selectedSkillNames = Set.unmodifiable(selectedSkillNames),
       selectedAgentIds = Set.unmodifiable(selectedAgentIds) {
    if (!installAllSkills && selectedSkillNames.isEmpty) {
      throw ArgumentError.value(
        selectedSkillNames,
        'selectedSkillNames',
        'must not be empty unless installAllSkills is true',
      );
    }
    if (!storeOnly && selectedAgentIds.isEmpty) {
      throw ArgumentError.value(
        selectedAgentIds,
        'selectedAgentIds',
        'must not be empty',
      );
    }
  }

  final ResolvedSkillSource source;
  final Set<String> selectedSkillNames;
  final Set<String> selectedAgentIds;
  final bool installAllSkills;
  final SkillActivationScope scope;
  final String? projectRootId;
  final bool storeOnly;
  final WorkspaceActivationMethod activationMethod;
}
