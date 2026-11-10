import 'dart:async';

import 'package:skills_manager/features/skills/data/services/skill_source_input_parser.dart';
import 'package:skills_manager/features/skills/data/services/smart_source_fallback.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_source_input_mode.dart';

import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';

enum AcquisitionStatus { idle, inspecting, ready, installing, success, failure }

enum SkillSelectionState { none, partial, all }

const _acquisitionUnset = Object();

final skillAcquisitionViewModelProvider =
    NotifierProvider<SkillAcquisitionViewModel, SkillAcquisitionState>(
      SkillAcquisitionViewModel.new,
    );

final class SkillAcquisitionState {
  const SkillAcquisitionState({
    this.inputMode = SkillSourceInputMode.smart,
    this.rawInput = '',
    this.smartInspected = false,
    this.advancedExpanded = false,
    this.requestedSkillNames = const {},
    this.requestedAgentIds = const [],
    this.requestGlobalScope = false,
    this.ignoredFlags = const [],
    this.unmatchedSkillNames = const [],
    this.unknownAgentIds = const [],
    this.parsed,
    Set<String> preselectedSlots = const {},
    this.step = AcquisitionStep.source,
    this.status = AcquisitionStatus.idle,
    this.sourceDraft = const SkillSourceDraft(),
    this.sourceKindChosen = false,
    this.inspection,
    this.selectedSlots = const {},
    this.selectedLocations = const {},
    this.agents = const [],
    this.scope = SkillActivationScope.global,
    this.storeOnly = false,
    this.projectRootId,
    this.progress,
    this.warnings = const [],
    this.failure,
    this.loadingTargets = false,
    this.memberIds,
    this.installTakeover,
    this.installedSlotKeys = const {},
  }) : _preselectedSlots = preselectedSlots;

  final SkillSourceInputMode inputMode;
  final String rawInput;
  final bool smartInspected;
  final bool advancedExpanded;
  final Set<String> requestedSkillNames;
  final List<String> requestedAgentIds;
  final bool requestGlobalScope;
  final List<String> ignoredFlags;
  final List<String> unmatchedSkillNames;
  final List<String> unknownAgentIds;
  final ParsedSkillSourceInput? parsed;
  final Set<String> _preselectedSlots;

  SkillSourceDetection get detection =>
      parsed?.detection ?? SkillSourceDetection.empty;

  Set<String> get preselectedSlots =>
      Set.unmodifiable(_preselectedSlots.intersection(selectedSlots));

  final AcquisitionStep step;
  final AcquisitionStatus status;
  final SkillSourceDraft sourceDraft;

  /// Whether the user has picked a Source kind yet.
  ///
  /// [SkillSourceDraft.kind] always carries a concrete kind because the
  /// Workspace needs one to resolve a Source. This flag is what separates
  /// "not chosen yet" from "chose the default kind", so the wizard can open
  /// with no card selected instead of pre-committing the user to Git.
  final bool sourceKindChosen;

  final SkillSourceInspection? inspection;
  final Set<String> selectedSlots;
  final Set<ActivationLocationKey> selectedLocations;
  final bool loadingTargets;
  final Set<String>? memberIds;
  final List<AgentOption> agents;
  final SkillActivationScope scope;
  final bool storeOnly;
  final String? projectRootId;
  final AcquisitionProgress? progress;
  final List<WorkspaceWarning> warnings;
  final AppFailure? failure;
  final WorkspaceInstallTakeoverDraft? installTakeover;

  /// Candidates of the current inspection that a managed Skill already
  /// occupies. Installing one fails with `sourceReplacementRequired`, so the
  /// selection step shows them as installed instead of letting the user find
  /// out at the last step.
  final Set<String> installedSlotKeys;

  /// Whether the source step can start an inspection: a kind is chosen and
  /// the locator holds more than whitespace.
  bool get canInspect =>
      !isBusy &&
      status != AcquisitionStatus.success &&
      (inputMode == SkillSourceInputMode.smart
          ? rawInput.trim().isNotEmpty
          : sourceKindChosen && sourceDraft.locator.trim().isNotEmpty);

  List<SkillCandidate> get selectableCandidates => [
    for (final candidate in inspection?.candidates ?? const <SkillCandidate>[])
      if (!installedSlotKeys.contains(candidate.slotKey)) candidate,
  ];

  List<ActivationLocationGroup> get locationGroups =>
      groupActivationLocations([
            for (final agent in agents)
              WorkspaceActivationTarget(
                agentId: agent.id,
                displayName: agent.displayName,
                detected: agent.detected,
                location: agent.location,
                scope: scope == SkillActivationScope.global
                    ? WorkspaceScope.global
                    : WorkspaceScope.project,
                projectRootId: projectRootId,
              ),
          ])
          .map(
            (group) => memberIds == null ? group : group.forMembers(memberIds!),
          )
          .toList();

  Set<String> get selectedAgentIds => {
    for (final group in locationGroups)
      if (selectedLocations.contains(group.key)) ...group.requestAgentIds,
  };

  List<ActivationLocationGroup> get visibleLocations =>
      locationGroups.where((g) => g.canActivate).toList();

  bool get isBusy =>
      status == AcquisitionStatus.inspecting ||
      status == AcquisitionStatus.installing;

  bool get canContinueToActivation =>
      step == AcquisitionStep.skills &&
      status == AcquisitionStatus.ready &&
      installTakeover == null &&
      !loadingTargets &&
      selectedSlots.isNotEmpty;

  bool get canInstall =>
      step == AcquisitionStep.activation &&
      status == AcquisitionStatus.ready &&
      selectedSlots.isNotEmpty &&
      (storeOnly || (!loadingTargets && selectedAgentIds.isNotEmpty)) &&
      (scope == SkillActivationScope.global || projectRootId != null);

  SkillSelectionState get skillSelectionState {
    final candidates = selectableCandidates;
    if (candidates.isEmpty) {
      return SkillSelectionState.none;
    }
    final selectedCandidateCount = candidates
        .where((candidate) => selectedSlots.contains(candidate.slotKey))
        .length;
    if (selectedCandidateCount == 0) return SkillSelectionState.none;
    if (selectedCandidateCount == candidates.length) {
      return SkillSelectionState.all;
    }
    return SkillSelectionState.partial;
  }

  SkillAcquisitionState copyWith({
    SkillSourceInputMode? inputMode,
    String? rawInput,
    bool? smartInspected,
    bool? advancedExpanded,
    Set<String>? requestedSkillNames,
    List<String>? requestedAgentIds,
    bool? requestGlobalScope,
    List<String>? ignoredFlags,
    List<String>? unmatchedSkillNames,
    List<String>? unknownAgentIds,
    Object? parsed = _acquisitionUnset,
    Set<String>? preselectedSlots,
    AcquisitionStep? step,
    AcquisitionStatus? status,
    SkillSourceDraft? sourceDraft,
    bool? sourceKindChosen,
    Object? inspection = _acquisitionUnset,
    Set<String>? selectedSlots,
    Set<ActivationLocationKey>? selectedLocations,
    bool? loadingTargets,
    Set<String>? memberIds,
    List<AgentOption>? agents,
    SkillActivationScope? scope,
    bool? storeOnly,
    Object? projectRootId = _acquisitionUnset,
    Object? progress = _acquisitionUnset,
    List<WorkspaceWarning>? warnings,
    Object? failure = _acquisitionUnset,
    Object? installTakeover = _acquisitionUnset,
    Set<String>? installedSlotKeys,
  }) => SkillAcquisitionState(
    inputMode: inputMode ?? this.inputMode,
    rawInput: rawInput ?? this.rawInput,
    smartInspected: smartInspected ?? this.smartInspected,
    advancedExpanded: advancedExpanded ?? this.advancedExpanded,
    requestedSkillNames: requestedSkillNames ?? this.requestedSkillNames,
    requestedAgentIds: requestedAgentIds ?? this.requestedAgentIds,
    requestGlobalScope: requestGlobalScope ?? this.requestGlobalScope,
    ignoredFlags: ignoredFlags ?? this.ignoredFlags,
    unmatchedSkillNames: unmatchedSkillNames ?? this.unmatchedSkillNames,
    unknownAgentIds: unknownAgentIds ?? this.unknownAgentIds,
    parsed: identical(parsed, _acquisitionUnset)
        ? this.parsed
        : parsed as ParsedSkillSourceInput?,
    preselectedSlots: preselectedSlots ?? _preselectedSlots,
    step: step ?? this.step,
    status: status ?? this.status,
    sourceDraft: sourceDraft ?? this.sourceDraft,
    sourceKindChosen: sourceKindChosen ?? this.sourceKindChosen,
    inspection: identical(inspection, _acquisitionUnset)
        ? this.inspection
        : inspection as SkillSourceInspection?,
    selectedSlots: selectedSlots ?? this.selectedSlots,
    selectedLocations: selectedLocations ?? this.selectedLocations,
    loadingTargets: loadingTargets ?? this.loadingTargets,
    memberIds: memberIds ?? this.memberIds,
    agents: agents ?? this.agents,
    scope: scope ?? this.scope,
    storeOnly: storeOnly ?? this.storeOnly,
    projectRootId: identical(projectRootId, _acquisitionUnset)
        ? this.projectRootId
        : projectRootId as String?,
    progress: identical(progress, _acquisitionUnset)
        ? this.progress
        : progress as AcquisitionProgress?,
    warnings: warnings ?? this.warnings,
    failure: identical(failure, _acquisitionUnset)
        ? this.failure
        : failure as AppFailure?,
    installTakeover: identical(installTakeover, _acquisitionUnset)
        ? this.installTakeover
        : installTakeover as WorkspaceInstallTakeoverDraft?,
    installedSlotKeys: installedSlotKeys ?? this.installedSlotKeys,
  );
}

final class SkillAcquisitionViewModel extends Notifier<SkillAcquisitionState> {
  final _parser = SkillSourceInputParser();
  String? _advancedSourceRef;
  String? _advancedRepositorySubpath;
  bool _inspectionCancelled = false;
  Future<void> Function()? _cancelActive;
  StreamSubscription<AcquisitionProgress>? _progressSubscription;
  var _targetRequest = 0;
  bool _waitingForInitialMembership = false;
  SkillAcquisitionState? _targetsBeforeLoad;

  SkillAcquisitionRepository? get _repository =>
      ref.read(skillAcquisitionRepositoryProvider);

  AcquisitionStatus get status => state.status;
  SkillSourceInspection? get inspection => state.inspection;
  List<AgentOption> get agents => state.agents;
  Set<String> get selectedSlots => state.selectedSlots;

  bool get sourceKindChosen => state.sourceKindChosen;
  bool get canInspect => state.canInspect;
  Set<String> get installedSlotKeys => state.installedSlotKeys;
  Set<ActivationLocationKey> get selectedLocations => state.selectedLocations;
  AcquisitionProgress? get progress => state.progress;
  List<WorkspaceWarning> get warnings => state.warnings;
  AppFailure? get failure => state.failure;
  bool get isBusy => state.isBusy;
  bool get canInstall {
    final members = ref.read(deviceAgentMembersProvider);
    return state.canInstall &&
        (state.storeOnly ||
            (!members.isLoading && !members.hasError && members.hasValue));
  }

  bool get isAvailable => _repository != null;
  bool get storeOnly => state.storeOnly;
  bool get loadingTargets => state.loadingTargets;
  Set<String>? get memberIds => state.memberIds;
  List<ActivationLocationGroup> get locationGroups => state.locationGroups;
  List<ActivationLocationGroup> get visibleLocations => state.visibleLocations;
  WorkspaceInstallTakeoverDraft? get installTakeover => state.installTakeover;
  SkillSelectionState get skillSelectionState => state.skillSelectionState;

  @override
  SkillAcquisitionState build() {
    ref.listen(activationCatalogRevisionProvider, (_, _) {
      Future.microtask(() {
        if (ref.mounted &&
            !state.isBusy &&
            state.step == AcquisitionStep.activation) {
          unawaited(
            loadTargets(scope: state.scope, projectRootId: state.projectRootId),
          );
        }
      });
    });
    ref.onDispose(() {
      final cancel = _cancelActive;
      if (cancel != null) unawaited(cancel());
      unawaited(_progressSubscription?.cancel());
    });
    return SkillAcquisitionState(
      inputMode: ref.read(skillSourceInputModeProvider),
    );
  }

  void reconcileAgentMembership(Set<String> memberIds) {
    if (state.isBusy) return;
    final updated = state.copyWith(memberIds: Set.unmodifiable(memberIds));
    state = updated.copyWith(
      selectedLocations: {
        for (final group in updated.visibleLocations)
          if (_waitingForInitialMembership
              ? _defaultLocations(updated).contains(group.key)
              : state.selectedLocations.contains(group.key))
            group.key,
      },
    );
    _waitingForInitialMembership = false;
  }

  void selectInputMode(SkillSourceInputMode mode) {
    if (state.isBusy || mode == state.inputMode) return;
    ref.read(skillSourceInputModeProvider.notifier).select(mode);
    if (mode == SkillSourceInputMode.typed) {
      final parsedDraft = state.parsed?.draft;
      final carry = parsedDraft != null && parsedDraft.locator.isNotEmpty;
      state = state.copyWith(inputMode: mode);
      _invalidateSource(
        carry ? _mergeAdvanced(parsedDraft) : state.sourceDraft,
        sourceKindChosen: carry ? true : null,
      );
    } else {
      final locator = state.sourceDraft.locator;
      _advancedSourceRef = state.sourceDraft.sourceRef;
      _advancedRepositorySubpath = state.sourceDraft.repositorySubpath;
      state = state.copyWith(inputMode: mode);
      updateRawInput(locator);
    }
  }

  SkillSourceDraft _mergeAdvanced(SkillSourceDraft draft) => draft.copyWith(
    sourceRef: draft.sourceRef.isEmpty
        ? _advancedSourceRef ?? ''
        : draft.sourceRef,
    repositorySubpath: draft.repositorySubpath.isEmpty
        ? _advancedRepositorySubpath ?? ''
        : draft.repositorySubpath,
  );

  void updateRawInput(String text) {
    if (state.isBusy) return;
    final parsed = text.trim().isEmpty
        ? null
        : _parser.parse(text, mode: SkillSourceInputMode.smart);
    final draft = _mergeAdvanced(parsed?.draft ?? const SkillSourceDraft());
    state = state.copyWith(
      rawInput: text,
      parsed: parsed,
      requestedSkillNames: parsed?.requestedSkillNames ?? const {},
      requestedAgentIds: parsed?.requestedAgentIds ?? const [],
      requestGlobalScope: parsed?.requestGlobalScope ?? false,
      ignoredFlags: parsed?.ignoredFlags ?? const [],
      advancedExpanded:
          state.advancedExpanded ||
          draft.sourceRef.isNotEmpty ||
          draft.repositorySubpath.isNotEmpty,
    );
    _invalidateSource(draft);
  }

  void toggleAdvanced() {
    if (state.isBusy) return;
    state = state.copyWith(advancedExpanded: !state.advancedExpanded);
  }

  void continueFromSmartResult() {
    if (state.inputMode != SkillSourceInputMode.smart ||
        !state.smartInspected ||
        state.status != AcquisitionStatus.ready) {
      return;
    }
    state = state.copyWith(step: AcquisitionStep.skills);
  }

  void selectSourceKind(SkillSourceKind kind) {
    // The first choice always lands, even when it matches the draft's default
    // kind: it is what reveals the rest of the form.
    if (state.isBusy ||
        (state.sourceKindChosen && kind == state.sourceDraft.kind)) {
      return;
    }
    final draft = state.sourceDraft;
    // A folder path and a URL never work for each other's kind, so carrying
    // one across turns a typo-free entry into an invalid-locator failure.
    // Git and Well-known both take URLs, so that switch keeps what was typed.
    final crossesLocalBoundary =
        state.sourceKindChosen &&
        (kind == SkillSourceKind.local) !=
            (draft.kind == SkillSourceKind.local);
    _invalidateSource(
      crossesLocalBoundary
          ? draft.copyWith(kind: kind, locator: '')
          : draft.copyWith(kind: kind),
      sourceKindChosen: true,
    );
  }

  void updateLocator(String value) {
    if (state.isBusy || value == state.sourceDraft.locator) return;
    final parsed = _parser.parse(
      value,
      mode: SkillSourceInputMode.typed,
      typedKind: state.sourceDraft.kind,
    );
    state = state.copyWith(
      requestedSkillNames: parsed.requestedSkillNames,
      requestedAgentIds: parsed.requestedAgentIds,
      requestGlobalScope: parsed.requestGlobalScope,
      ignoredFlags: parsed.ignoredFlags,
    );
    _invalidateSource(
      state.sourceDraft.copyWith(
        locator: parsed.fromInstallCommand ? parsed.draft.locator : value,
      ),
    );
  }

  void updateSourceRef(String value) {
    if (state.isBusy || value == state.sourceDraft.sourceRef) return;
    _advancedSourceRef = value;
    _invalidateSource(state.sourceDraft.copyWith(sourceRef: value));
  }

  void updateRepositorySubpath(String value) {
    if (state.isBusy || value == state.sourceDraft.repositorySubpath) return;
    _advancedRepositorySubpath = value;
    _invalidateSource(state.sourceDraft.copyWith(repositorySubpath: value));
  }

  Future<void> inspect() async {
    final repository = _repository;
    if (state.isBusy || repository == null) return;
    final smart = state.inputMode == SkillSourceInputMode.smart;
    final parsed = state.parsed;
    final draft = smart
        ? parsed?.draft.copyWith(
            sourceRef: state.sourceDraft.sourceRef,
            repositorySubpath: state.sourceDraft.repositorySubpath,
          )
        : state.sourceDraft;
    if (draft == null || draft.locator.trim().isEmpty) return;
    _inspectionCancelled = false;
    state = state.copyWith(
      step: AcquisitionStep.source,
      status: AcquisitionStatus.inspecting,
      smartInspected: false,
      loadingTargets: false,
      inspection: null,
      selectedSlots: const {},
      preselectedSlots: const {},
      unmatchedSkillNames: const [],
      unknownAgentIds: const [],
      failure: null,
      warnings: const [],
    );
    try {
      var completion = await _inspectAttempt(repository, draft);
      if (!ref.mounted) return;
      _mergeCompletionWarnings(completion);
      if (smart &&
          parsed?.detection == SkillSourceDetection.webUrl &&
          completion is WorkspaceFailed<SkillSourceInspection> &&
          shouldTryWebSourceAsGit(completion.failure)) {
        if (_inspectionCancelled) {
          await _fail(
            WorkspaceFailure(
              code: WorkspaceErrorCode.operationCancelled,
              operation: WorkspaceOperationKind.inspectSource,
            ),
            StackTrace.current,
            operation: SkillAcquisitionOperation.inspectSource,
          );
          return;
        }
        completion = await _inspectAttempt(
          repository,
          draft.copyWith(kind: SkillSourceKind.git),
          friendlyWebFailure: true,
        );
        if (!ref.mounted) return;
        _mergeCompletionWarnings(completion);
      }
      switch (completion) {
        case WorkspaceCompleted(:final value):
          final installed = _installedSlotKeys(value.candidates);
          final defaults = {
            for (final candidate in value.candidates)
              if (!installed.contains(candidate.slotKey)) candidate.slotKey,
          };
          final requested = state.requestedSkillNames;
          final all = requested.isEmpty || requested.contains('*');
          final matched = <String>{};
          final unmatched = <String>[];
          if (!all) {
            for (final name in requested) {
              final candidates = value.candidates.where(
                (candidate) =>
                    candidate.declaredName.toLowerCase() ==
                        name.toLowerCase() ||
                    candidate.slotKey.toLowerCase() == name.toLowerCase(),
              );
              if (candidates.isEmpty) unmatched.add(name);
              matched.addAll(candidates.map((candidate) => candidate.slotKey));
            }
          }
          final selected = all || matched.isEmpty
              ? defaults
              : matched.difference(installed);
          state = state.copyWith(
            step: smart ? AcquisitionStep.source : AcquisitionStep.skills,
            smartInspected: smart,
            inspection: value,
            installedSlotKeys: installed,
            selectedSlots: Set.unmodifiable(selected),
            preselectedSlots: Set.unmodifiable(
              requested.contains('*')
                  ? defaults
                  : matched.difference(installed),
            ),
            unmatchedSkillNames: List.unmodifiable(unmatched),
            status: AcquisitionStatus.ready,
            progress: null,
          );
          await _stopWatching();
        case WorkspaceFailed(:final failure):
          await _fail(
            failure,
            StackTrace.current,
            operation: SkillAcquisitionOperation.inspectSource,
          );
        case WorkspaceCommittedPending():
          state = state.copyWith(
            status: AcquisitionStatus.idle,
            progress: null,
          );
          await _stopWatching();
          if (ref.mounted) _publishFinalizationPending(completion);
      }
    } on Object catch (error, stackTrace) {
      await _fail(
        error,
        stackTrace,
        operation: SkillAcquisitionOperation.inspectSource,
      );
    }
  }

  bool _isWebGitFailure(WorkspaceFailure failure) => switch (failure.code) {
    WorkspaceErrorCode.gitFailed ||
    WorkspaceErrorCode.sourceAuthenticationRequired ||
    WorkspaceErrorCode.transportRejected => true,
    _ => false,
  };

  Future<WorkspaceCompletion<SkillSourceInspection>> _inspectAttempt(
    SkillAcquisitionRepository repository,
    SkillSourceDraft draft, {
    bool friendlyWebFailure = false,
  }) async {
    final analytics = ref.read(appAnalyticsProvider);
    final sourceKind = _analyticsSourceKind(draft.kind);
    final stopwatch = Stopwatch()..start();
    var analyticsRecorded = false;
    try {
      final task = repository.inspect(draft);
      final warnings = state.warnings;
      _watch(task);
      state = state.copyWith(
        warnings: _mergeWarnings(warnings, state.warnings),
      );
      final completion = await task.completed;
      stopwatch.stop();
      final friendly =
          friendlyWebFailure &&
              completion is WorkspaceFailed<SkillSourceInspection> &&
              _isWebGitFailure(completion.failure)
          ? SkillAcquisitionException(
              operation: SkillAcquisitionOperation.inspectSource,
              code: SkillAcquisitionErrorCode.webSourceHasNoSkills,
              context: {'locatorHost': Uri.tryParse(draft.locator)?.host ?? ''},
            )
          : null;
      analytics.track(
        AppAnalyticsEvent.sourceInspection(
          sourceKind: sourceKind,
          outcome: switch (completion) {
            WorkspaceCompleted(:final value) =>
              value.candidates.isEmpty
                  ? SourceInspectionAnalyticsOutcome.empty
                  : SourceInspectionAnalyticsOutcome.success,
            WorkspaceFailed(:final failure)
                when failure.code == WorkspaceErrorCode.operationCancelled =>
              SourceInspectionAnalyticsOutcome.cancelled,
            _ => SourceInspectionAnalyticsOutcome.failed,
          },
          duration: stopwatch.elapsed,
          itemCount: switch (completion) {
            WorkspaceCompleted(:final value) => value.candidates.length,
            _ => null,
          },
          errorCode:
              friendly?.codeKey ??
              switch (completion) {
                WorkspaceFailed(:final failure) => appAnalyticsErrorCode(
                  failure,
                ),
                WorkspaceCommittedPending() => 'unexpected',
                _ => null,
              },
        ),
      );
      analyticsRecorded = true;
      if (friendly != null) {
        if (ref.mounted) _mergeCompletionWarnings(completion);
        throw friendly;
      }
      return completion;
    } on Object catch (error) {
      stopwatch.stop();
      if (!analyticsRecorded) {
        analytics.track(
          AppAnalyticsEvent.sourceInspection(
            sourceKind: sourceKind,
            outcome: SourceInspectionAnalyticsOutcome.failed,
            duration: stopwatch.elapsed,
            errorCode: _analyticsErrorCode(error),
          ),
        );
      }
      rethrow;
    }
  }

  /// Starts the source step over with the same form and inspects again.
  ///
  /// Used when a later step learns the inspected Source is no longer what it
  /// was, so the user sees fresh candidates instead of replaying an install.
  Future<void> reinspect() async {
    if (state.isBusy) return;
    _invalidateSource(state.sourceDraft);
    await inspect();
  }

  void toggleSkill(String slotKey, bool selected) {
    if (state.step != AcquisitionStep.skills ||
        state.status != AcquisitionStatus.ready ||
        state.installedSlotKeys.contains(slotKey)) {
      return;
    }
    final next = {...state.selectedSlots};
    selected ? next.add(slotKey) : next.remove(slotKey);
    state = state.copyWith(selectedSlots: Set<String>.unmodifiable(next));
  }

  void toggleAllSkills(bool selected) {
    if (state.step != AcquisitionStep.skills ||
        state.status != AcquisitionStatus.ready) {
      return;
    }
    final candidates = state.selectableCandidates;
    if (candidates.isEmpty) return;
    state = state.copyWith(
      selectedSlots: selected
          ? Set<String>.unmodifiable({
              for (final candidate in candidates) candidate.slotKey,
            })
          : const {},
    );
  }

  Future<void> continueToActivation(List<SkillProjectRoot> roots) async {
    if (!state.canContinueToActivation) return;
    if (state.requestGlobalScope) {
      state = state.copyWith(scope: SkillActivationScope.global);
    }
    final projectRootId = state.scope == SkillActivationScope.project
        ? _validProjectRootId(roots)
        : null;
    state = state.copyWith(
      step: AcquisitionStep.activation,
      projectRootId: projectRootId,
    );
    await loadTargets(scope: state.scope, projectRootId: projectRootId);
  }

  void back() {
    if (state.isBusy) return;
    switch (state.step) {
      case AcquisitionStep.source:
        return;
      case AcquisitionStep.skills:
        _targetRequest += 1;
        if (state.inputMode == SkillSourceInputMode.smart) {
          state = state.copyWith(
            step: AcquisitionStep.source,
            smartInspected: true,
            failure: null,
          );
          return;
        }
        state = state.copyWith(
          step: AcquisitionStep.source,
          status: AcquisitionStatus.idle,
          inspection: null,
          selectedSlots: const {},
          installedSlotKeys: const {},
          agents: const [],
          selectedLocations: const {},
          progress: null,
          warnings: const [],
          failure: null,
        );
      case AcquisitionStep.activation:
        _targetRequest += 1;
        state = state.copyWith(
          step: AcquisitionStep.skills,
          loadingTargets: false,
          agents: const [],
          selectedLocations: const {},
          projectRootId: null,
          failure: null,
        );
    }
  }

  Future<void> selectScope(
    SkillActivationScope scope,
    List<SkillProjectRoot> roots,
  ) async {
    if (state.isBusy) return;
    final projectRootId = scope == SkillActivationScope.project
        ? _validProjectRootId(roots)
        : null;
    await loadTargets(scope: scope, projectRootId: projectRootId);
  }

  Future<void> selectProjectRoot(String projectRootId) => loadTargets(
    scope: SkillActivationScope.project,
    projectRootId: projectRootId,
  );

  Future<void> reconcileProjectRoots(List<SkillProjectRoot> roots) async {
    if (state.scope != SkillActivationScope.project || state.isBusy) return;
    final projectRootId = _validProjectRootId(roots);
    if (projectRootId == null) {
      _targetRequest += 1;
      state = state.copyWith(
        projectRootId: null,
        loadingTargets: false,
        agents: const [],
        selectedLocations: const {},
        failure: null,
      );
      return;
    }
    await loadTargets(
      scope: SkillActivationScope.project,
      projectRootId: projectRootId,
    );
  }

  String? _validProjectRootId(List<SkillProjectRoot> roots) {
    final selected = state.projectRootId;
    if (selected != null && roots.any((root) => root.id == selected)) {
      return selected;
    }
    return roots.isEmpty ? null : roots.first.id;
  }

  Future<void> loadTargets({
    required SkillActivationScope scope,
    String? projectRootId,
  }) async {
    final repository = _repository;
    if (repository == null || state.isBusy) return;
    final request = ++_targetRequest;
    final previous = state.loadingTargets ? _targetsBeforeLoad ?? state : state;
    final preserve =
        state.scope == scope &&
        state.projectRootId == projectRootId &&
        previous.agents.isNotEmpty;
    final selectedBefore = previous.selectedLocations;
    _targetsBeforeLoad = preserve ? previous : null;
    state = state.copyWith(
      scope: scope,
      projectRootId: projectRootId,
      agents: const [],
      selectedLocations: const {},
      failure: null,
      loadingTargets: true,
    );
    if (scope == SkillActivationScope.project && projectRootId == null) {
      state = state.copyWith(loadingTargets: false);
      return;
    }
    try {
      final completion = await repository.inspectTargets(
        scope: scope,
        projectRootId: projectRootId,
      );
      if (!ref.mounted || request != _targetRequest) return;
      switch (completion) {
        case WorkspaceCompleted(:final value, :final warnings):
          final members = ref.read(deviceAgentMembersProvider);
          _waitingForInitialMembership = !preserve && members.value == null;
          final next = state.copyWith(
            agents: List.unmodifiable(value),
            memberIds: members.value ?? const {},
          );
          final requested = state.requestedAgentIds;
          final known = {
            for (final group in next.locationGroups) ...group.requestAgentIds,
          };
          state = next.copyWith(
            selectedLocations: preserve
                ? Set.unmodifiable({
                    for (final group in next.visibleLocations)
                      if (selectedBefore.contains(group.key)) group.key,
                  })
                : _defaultLocations(next),
            unknownAgentIds: preserve
                ? state.unknownAgentIds
                : List.unmodifiable(
                    requested.where((id) => id != '*' && !known.contains(id)),
                  ),
            warnings: _mergeWarnings(state.warnings, warnings),
          );
        case WorkspaceFailed(:final failure, :final warnings):
          _applyTargetFailure(failure, warnings);
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
          :final warnings,
        ):
          _applyTargetFailure(
            WorkspaceFailure(
              code: WorkspaceErrorCode.operationFailed,
              operation: WorkspaceOperationKind.inspectActivationTargets,
              context: {
                'operationId': operationId,
                'committedRevision': committedRevision,
                'reason': 'readOnlyOperationCommittedPending',
              },
              warnings: warnings,
            ),
            warnings,
          );
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted || request != _targetRequest) return;
      final failure = ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: WorkspaceOperationKind.inspectActivationTargets.name,
            message: AppFailureMessage.activation,
          );
      state = state.copyWith(
        failure: failure,
        warnings: _mergeWarnings(
          state.warnings,
          failure.warnings.whereType<WorkspaceWarning>(),
        ),
      );
      _publishFailure(failure);
    } finally {
      if (ref.mounted && request == _targetRequest) {
        _targetsBeforeLoad = null;
        state = state.copyWith(loadingTargets: false);
      }
    }
  }

  Set<ActivationLocationKey> _defaultLocations(SkillAcquisitionState next) {
    final defaults = {for (final group in next.visibleLocations) group.key};
    final requested = next.requestedAgentIds;
    if (requested.isEmpty || requested.contains('*')) {
      return Set.unmodifiable(defaults);
    }
    final matches = {
      for (final group in next.visibleLocations)
        if (group.requestAgentIds.any(requested.contains)) group.key,
    };
    return Set.unmodifiable(matches.isEmpty ? defaults : matches);
  }

  void _applyTargetFailure(
    WorkspaceFailure failure,
    List<WorkspaceWarning> warnings,
  ) {
    final appFailure = ref
        .read(appFailureReporterProvider)
        .capture(
          failure,
          StackTrace.current,
          operationKey: WorkspaceOperationKind.inspectActivationTargets.name,
          message: AppFailureMessage.activation,
        );
    state = state.copyWith(
      failure: appFailure,
      warnings: _mergeWarnings(state.warnings, [
        ...warnings,
        ...appFailure.warnings.whereType<WorkspaceWarning>(),
      ]),
    );
    _publishFailure(appFailure);
  }

  void toggleLocation(ActivationLocationKey key, bool selected) {
    if (state.isBusy) return;
    if (!state.visibleLocations.any((g) => g.key == key)) return;
    final next = {...state.selectedLocations};
    selected ? next.add(key) : next.remove(key);
    state = state.copyWith(selectedLocations: Set.unmodifiable(next));
  }

  void retryTargets() =>
      ref.read(activationCatalogRevisionProvider.notifier).refresh();

  void selectAllLocations(
    bool selected, {
    Iterable<ActivationLocationKey>? visibleKeys,
  }) {
    if (state.isBusy || state.loadingTargets) return;
    final valid = state.visibleLocations.map((g) => g.key).toSet();
    final keys = (visibleKeys ?? state.visibleLocations.map((g) => g.key))
        .where(valid.contains);
    final next = {...state.selectedLocations};
    selected ? next.addAll(keys) : next.removeAll(keys);
    state = state.copyWith(selectedLocations: Set.unmodifiable(next));
  }

  void setStoreOnly(bool value) {
    if (state.isBusy) return;
    state = state.copyWith(storeOnly: value);
  }

  Future<void> install() async {
    if (!state.storeOnly) {
      final members = ref.read(deviceAgentMembersProvider);
      if (members.isLoading || members.hasError || members.value == null) {
        return;
      }
      final reconciled = state.copyWith(memberIds: members.value!);
      state = reconciled.copyWith(
        selectedLocations: {
          for (final group in reconciled.visibleLocations)
            if (state.selectedLocations.contains(group.key)) group.key,
        },
      );
    }
    final repository = _repository;
    final inspection = state.inspection;
    if (repository == null || !state.canInstall || inspection == null) return;
    final analytics = ref.read(appAnalyticsProvider);
    final sourceKind = _analyticsSourceKind(inspection.source.kind);
    final scope = state.storeOnly
        ? AppAnalyticsScope.none
        : _analyticsScope(state.scope);
    final itemCount = state.selectedSlots.length;
    final targetCount = state.storeOnly ? 0 : state.selectedLocations.length;
    final stopwatch = Stopwatch()..start();
    var analyticsRecorded = false;
    state = state.copyWith(
      status: AcquisitionStatus.installing,
      failure: null,
      installTakeover: null,
    );
    var operation = SkillAcquisitionOperation.installSkills;
    try {
      final allSelected =
          state.selectedSlots.length == inspection.candidates.length;
      final selectedNames = {
        for (final candidate in inspection.candidates)
          if (state.selectedSlots.contains(candidate.slotKey))
            candidate.declaredName,
      };
      final task = repository.install(
        InstallSelection(
          source: inspection.source,
          selectedSkillNames: selectedNames,
          selectedAgentIds: state.selectedAgentIds,
          installAllSkills: allSelected,
          scope: state.scope,
          projectRootId: state.projectRootId,
          storeOnly: state.storeOnly,
          activationMethod: ref.read(globalActivationMethodProvider),
        ),
      );
      _watch(task);
      final completion = await task.completed;
      stopwatch.stop();
      analytics.track(
        AppAnalyticsEvent.skillInstall(
          sourceKind: sourceKind,
          scope: scope,
          outcome: switch (completion) {
            WorkspaceCompleted(:final value) => switch (value) {
              AcquisitionInstallCompleted(:final receipt) =>
                receipt.affectedSlotKeys.isEmpty
                    ? SkillInstallAnalyticsOutcome.noChange
                    : SkillInstallAnalyticsOutcome.success,
              AcquisitionInstallTakeoverRequired() =>
                SkillInstallAnalyticsOutcome.takeoverRequired,
            },
            WorkspaceFailed(:final failure)
                when failure.code == WorkspaceErrorCode.operationCancelled =>
              SkillInstallAnalyticsOutcome.cancelled,
            WorkspaceFailed() => SkillInstallAnalyticsOutcome.failed,
            WorkspaceCommittedPending() =>
              SkillInstallAnalyticsOutcome.finalizationPending,
          },
          duration: stopwatch.elapsed,
          itemCount: itemCount,
          targetCount: targetCount,
          errorCode: switch (completion) {
            WorkspaceFailed(:final failure) => appAnalyticsErrorCode(failure),
            _ => null,
          },
        ),
      );
      analyticsRecorded = true;
      if (!ref.mounted) return;
      _mergeCompletionWarnings(completion);
      switch (completion) {
        case WorkspaceCompleted(:final value):
          switch (value) {
            case AcquisitionInstallCompleted():
              await _completeInstall();
            case AcquisitionInstallTakeoverRequired(:final draft):
              state = state.copyWith(
                status: AcquisitionStatus.ready,
                progress: null,
                installTakeover: draft,
              );
              await _stopWatching();
          }
        case WorkspaceFailed(:final failure):
          await _fail(failure, StackTrace.current, operation: operation);
        case WorkspaceCommittedPending():
          state = state.copyWith(
            status: AcquisitionStatus.ready,
            progress: null,
          );
          await _stopWatching();
          if (ref.mounted) {
            _publishFinalizationPending(completion);
          }
      }
    } on Object catch (error, stackTrace) {
      if (stopwatch.isRunning) stopwatch.stop();
      if (!analyticsRecorded) {
        analytics.track(
          AppAnalyticsEvent.skillInstall(
            sourceKind: sourceKind,
            scope: scope,
            outcome: SkillInstallAnalyticsOutcome.failed,
            duration: stopwatch.elapsed,
            itemCount: itemCount,
            targetCount: targetCount,
            errorCode: _analyticsErrorCode(error),
          ),
        );
      }
      await _fail(error, stackTrace, operation: operation);
    }
  }

  Future<void> confirmInstallTakeover() async {
    final repository = _repository;
    final draft = state.installTakeover;
    if (repository == null || draft == null || state.isBusy) return;
    final analytics = ref.read(appAnalyticsProvider);
    final sourceKind = _analyticsSourceKind(state.inspection!.source.kind);
    final scope = state.storeOnly
        ? AppAnalyticsScope.none
        : _analyticsScope(state.scope);
    final itemCount = state.selectedSlots.length;
    final targetCount = state.storeOnly ? 0 : state.selectedLocations.length;
    final stopwatch = Stopwatch()..start();
    var analyticsRecorded = false;
    state = state.copyWith(
      status: AcquisitionStatus.installing,
      failure: null,
      installTakeover: null,
    );
    try {
      final task = repository.confirmInstallTakeover(draft);
      _watch(task);
      final completion = await task.completed;
      stopwatch.stop();
      analytics.track(
        AppAnalyticsEvent.skillInstall(
          sourceKind: sourceKind,
          scope: scope,
          outcome: switch (completion) {
            WorkspaceCompleted(:final value) =>
              value.affectedSlotKeys.isEmpty
                  ? SkillInstallAnalyticsOutcome.noChange
                  : SkillInstallAnalyticsOutcome.success,
            WorkspaceFailed(:final failure)
                when failure.code == WorkspaceErrorCode.operationCancelled =>
              SkillInstallAnalyticsOutcome.cancelled,
            WorkspaceFailed() => SkillInstallAnalyticsOutcome.failed,
            WorkspaceCommittedPending() =>
              SkillInstallAnalyticsOutcome.finalizationPending,
          },
          duration: stopwatch.elapsed,
          itemCount: itemCount,
          targetCount: targetCount,
          errorCode: switch (completion) {
            WorkspaceFailed(:final failure) => appAnalyticsErrorCode(failure),
            _ => null,
          },
        ),
      );
      analyticsRecorded = true;
      if (!ref.mounted) return;
      _mergeCompletionWarnings(completion);
      switch (completion) {
        case WorkspaceCompleted():
          await _completeInstall();
        case WorkspaceFailed(:final failure):
          await _fail(
            failure,
            StackTrace.current,
            operation: SkillAcquisitionOperation.confirmInstallTakeover,
          );
        case WorkspaceCommittedPending():
          state = state.copyWith(
            status: AcquisitionStatus.ready,
            progress: null,
          );
          await _stopWatching();
          if (ref.mounted) _publishFinalizationPending(completion);
      }
    } on Object catch (error, stackTrace) {
      if (stopwatch.isRunning) stopwatch.stop();
      if (!analyticsRecorded) {
        analytics.track(
          AppAnalyticsEvent.skillInstall(
            sourceKind: sourceKind,
            scope: scope,
            outcome: SkillInstallAnalyticsOutcome.failed,
            duration: stopwatch.elapsed,
            itemCount: itemCount,
            targetCount: targetCount,
            errorCode: _analyticsErrorCode(error),
          ),
        );
      }
      await _fail(
        error,
        stackTrace,
        operation: SkillAcquisitionOperation.confirmInstallTakeover,
      );
    }
  }

  void dismissInstallTakeover() {
    if (state.isBusy) return;
    state = state.copyWith(installTakeover: null);
  }

  Future<void> _completeInstall() async {
    state = state.copyWith(
      status: AcquisitionStatus.success,
      progress: null,
      installTakeover: null,
    );
    await _stopWatching();
    if (!ref.mounted) return;
    final notifications = ref.read(appNotificationControllerProvider.notifier);
    if (state.warnings.isEmpty) {
      notifications.success(AppNotificationMessage.skillsInstalled);
    } else {
      notifications.warning(AppNotificationMessage.completedWithWarnings);
    }
  }

  Future<void> cancel() async {
    if (state.status == AcquisitionStatus.inspecting) {
      _inspectionCancelled = true;
    }
    final cancel = _cancelActive;
    if (cancel != null) await cancel();
  }

  void reset() {
    if (state.isBusy) return;
    _targetRequest += 1;
    _advancedSourceRef = null;
    _advancedRepositorySubpath = null;
    _waitingForInitialMembership = false;
    _targetsBeforeLoad = null;
    state = SkillAcquisitionState(
      inputMode: ref.read(skillSourceInputModeProvider),
    );
  }

  Set<String> _installedSlotKeys(List<SkillCandidate> candidates) {
    final snapshot = ref.read(workspaceSnapshotProvider).value;
    if (snapshot == null) return const {};
    return Set<String>.unmodifiable({
      for (final candidate in candidates)
        if (snapshot.findSkillBySlotKey(candidate.slotKey) != null)
          candidate.slotKey,
    });
  }

  /// The managed Skill that occupies [slotKey], if any.
  WorkspaceSkill? installedSkill(String slotKey) =>
      ref.read(workspaceSnapshotProvider).value?.findSkillBySlotKey(slotKey);

  void _invalidateSource(SkillSourceDraft draft, {bool? sourceKindChosen}) {
    _targetRequest += 1;
    state = state.copyWith(
      step: AcquisitionStep.source,
      status: AcquisitionStatus.idle,
      sourceDraft: draft,
      smartInspected: false,
      preselectedSlots: const {},
      unmatchedSkillNames: const [],
      unknownAgentIds: const [],
      sourceKindChosen: sourceKindChosen,
      inspection: null,
      selectedSlots: const {},
      installedSlotKeys: const {},
      agents: const [],
      selectedLocations: const {},
      progress: null,
      warnings: const [],
      failure: null,
    );
  }

  void _watch<T>(AcquisitionTask<T> task) {
    unawaited(_progressSubscription?.cancel());
    _cancelActive = task.cancel;
    state = state.copyWith(
      progress: task.current,
      warnings: _mergeWarnings(const [], task.current.warnings),
    );
    _progressSubscription = task.states.listen((progress) {
      if (!ref.mounted) return;
      state = state.copyWith(
        progress: progress,
        warnings: _mergeWarnings(state.warnings, progress.warnings),
      );
    });
  }

  Future<void> _fail(
    Object error,
    StackTrace stackTrace, {
    required SkillAcquisitionOperation operation,
  }) async {
    if (!ref.mounted) return;
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(
          error,
          stackTrace,
          operationKey: operation.name,
          message: _failureMessage(operation),
        );
    final warnings = _mergeWarnings(
      state.warnings,
      failure.warnings.whereType<WorkspaceWarning>(),
    );
    if (failure.message == AppFailureMessage.operationCancelled) {
      state = state.copyWith(
        status: state.step == AcquisitionStep.activation
            ? AcquisitionStatus.ready
            : AcquisitionStatus.idle,
        progress: null,
        failure: null,
        warnings: warnings,
      );
      await _stopWatching();
      if (!ref.mounted) return;
      ref
          .read(appNotificationControllerProvider.notifier)
          .info(AppNotificationMessage.operationCancelled);
      return;
    }
    if (failure.message == AppFailureMessage.developerToolsRequired) {
      // Inline only, at whatever step it happened: the dialog carries setup
      // guidance the user must act on, and a toast would vanish behind the
      // operating system's own install dialog with nowhere to go next.
      state = state.copyWith(
        status: AcquisitionStatus.failure,
        progress: null,
        failure: failure,
        warnings: warnings,
      );
      await _stopWatching();
      return;
    }
    state = state.copyWith(
      status: state.step == AcquisitionStep.activation
          ? AcquisitionStatus.ready
          : AcquisitionStatus.failure,
      progress: null,
      failure: failure,
      warnings: warnings,
    );
    await _stopWatching();
    if (!ref.mounted) return;
    _publishFailure(failure);
  }

  AppFailureMessage _failureMessage(
    SkillAcquisitionOperation operation,
  ) => switch (operation) {
    SkillAcquisitionOperation.resolveSource =>
      AppFailureMessage.invalidSourceInput,
    SkillAcquisitionOperation.inspectSource => AppFailureMessage.inspectSource,
    SkillAcquisitionOperation.installSkills => AppFailureMessage.installSkills,
    SkillAcquisitionOperation.confirmInstallTakeover =>
      AppFailureMessage.installSkills,
    SkillAcquisitionOperation.refreshAfterInstall =>
      AppFailureMessage.refreshAfterInstall,
  };

  void _publishFailure(AppFailure failure) {
    ref
        .read(appNotificationControllerProvider.notifier)
        .publish(AppNotification.failure(failure));
  }

  void _mergeCompletionWarnings<T>(WorkspaceCompletion<T> completion) {
    state = state.copyWith(
      warnings: _mergeWarnings(state.warnings, completion.warnings),
    );
  }

  void _publishFinalizationPending<T>(WorkspaceCommittedPending<T> pending) =>
      ref
          .read(workspaceFinalizationCoordinatorProvider.notifier)
          .register(
            WorkspaceCommittedPending<void>(
              operationId: pending.operationId,
              committedRevision: pending.committedRevision,
              warnings: state.warnings,
            ),
          );

  Future<void> _stopWatching() async {
    _cancelActive = null;
    final subscription = _progressSubscription;
    _progressSubscription = null;
    await subscription?.cancel();
  }

  List<WorkspaceWarning> _mergeWarnings(
    Iterable<WorkspaceWarning> existing,
    Iterable<WorkspaceWarning> incoming,
  ) {
    final warnings = <Object, WorkspaceWarning>{
      for (final warning in existing) workspaceWarningKey(warning): warning,
    };
    for (final warning in incoming) {
      warnings[workspaceWarningKey(warning)] = warning;
    }
    return List.unmodifiable(warnings.values);
  }
}

AppAnalyticsSourceKind _analyticsSourceKind(SkillSourceKind sourceKind) =>
    switch (sourceKind) {
      SkillSourceKind.local => AppAnalyticsSourceKind.local,
      SkillSourceKind.git => AppAnalyticsSourceKind.git,
      SkillSourceKind.wellKnown => AppAnalyticsSourceKind.wellKnown,
    };

AppAnalyticsScope _analyticsScope(SkillActivationScope scope) =>
    switch (scope) {
      SkillActivationScope.global => AppAnalyticsScope.global,
      SkillActivationScope.project => AppAnalyticsScope.project,
    };

String? _analyticsErrorCode(Object error) => switch (error) {
  AppFailure() => appAnalyticsErrorCode(error),
  _ => 'unexpected',
};
