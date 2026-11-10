import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_input_parser.dart';
import 'package:skills_manager/features/skills/data/services/smart_source_fallback.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_source_input_mode.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

/// The Replace Source wizard walks the same three questions as Add Skill —
/// which Source, which Skill in it, then act — but "act" is a single-Skill
/// replacement rather than a multi-Skill install, so it gets its own step
/// enum and single-selection state instead of reusing [AcquisitionStep].
enum ReplacementStep { source, select, replace }

enum ReplacementStatus { idle, inspecting, ready, failure }

final sourceReplacementViewModelProvider =
    NotifierProvider<SourceReplacementViewModel, SourceReplacementState>(
      SourceReplacementViewModel.new,
    );

final class SourceReplacementState {
  const SourceReplacementState({
    this.target,
    this.step = ReplacementStep.source,
    this.status = ReplacementStatus.idle,
    this.inputMode = SkillSourceInputMode.smart,
    this.rawInput = '',
    this.parsed,
    this.advancedExpanded = false,
    this.sourceDraft = const SkillSourceDraft(),
    this.sourceKindChosen = false,
    this.inspection,
    this.selectedSlotKey,
    this.progress,
    this.warnings = const [],
    this.failure,
  });

  final InstalledSkill? target;
  final ReplacementStep step;
  final ReplacementStatus status;

  /// Step one offers the same smart paste box and typed cards as Add Skill,
  /// sharing its remembered mode.
  final SkillSourceInputMode inputMode;
  final String rawInput;
  final ParsedSkillSourceInput? parsed;
  final bool advancedExpanded;
  final SkillSourceDraft sourceDraft;
  final bool sourceKindChosen;
  final SkillSourceInspection? inspection;
  final String? selectedSlotKey;
  final AcquisitionProgress? progress;
  final List<WorkspaceWarning> warnings;
  final AppFailure? failure;

  bool get isBusy => status == ReplacementStatus.inspecting;

  SkillSourceDetection get detection =>
      parsed?.detection ?? SkillSourceDetection.empty;

  bool get canInspect =>
      !isBusy &&
      (inputMode == SkillSourceInputMode.smart
          ? sourceDraft.locator.trim().isNotEmpty
          : sourceKindChosen);

  bool get canContinueToReplace =>
      step == ReplacementStep.select &&
      status == ReplacementStatus.ready &&
      selectedSlotKey != null;

  SourceReplacementState copyWith({
    InstalledSkill? target,
    ReplacementStep? step,
    ReplacementStatus? status,
    SkillSourceInputMode? inputMode,
    String? rawInput,
    ParsedSkillSourceInput? parsed,
    bool clearParsed = false,
    bool? advancedExpanded,
    SkillSourceDraft? sourceDraft,
    bool? sourceKindChosen,
    SkillSourceInspection? inspection,
    bool clearInspection = false,
    String? selectedSlotKey,
    bool clearSelectedSlotKey = false,
    AcquisitionProgress? progress,
    bool clearProgress = false,
    List<WorkspaceWarning>? warnings,
    AppFailure? failure,
    bool clearFailure = false,
  }) => SourceReplacementState(
    target: target ?? this.target,
    step: step ?? this.step,
    status: status ?? this.status,
    inputMode: inputMode ?? this.inputMode,
    rawInput: rawInput ?? this.rawInput,
    parsed: clearParsed ? null : parsed ?? this.parsed,
    advancedExpanded: advancedExpanded ?? this.advancedExpanded,
    sourceDraft: sourceDraft ?? this.sourceDraft,
    sourceKindChosen: sourceKindChosen ?? this.sourceKindChosen,
    inspection: clearInspection ? null : inspection ?? this.inspection,
    selectedSlotKey: clearSelectedSlotKey
        ? null
        : selectedSlotKey ?? this.selectedSlotKey,
    progress: clearProgress ? null : progress ?? this.progress,
    warnings: warnings ?? this.warnings,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

final class SourceReplacementViewModel
    extends Notifier<SourceReplacementState> {
  Future<void> Function()? _cancelActive;
  StreamSubscription<AcquisitionProgress>? _progressSubscription;
  final _parser = SkillSourceInputParser();

  SkillAcquisitionRepository? get _repository =>
      ref.read(skillAcquisitionRepositoryProvider);

  @override
  SourceReplacementState build() {
    ref.onDispose(() {
      final cancel = _cancelActive;
      if (cancel != null) unawaited(cancel());
      unawaited(_progressSubscription?.cancel());
    });
    return SourceReplacementState(
      inputMode: ref.read(skillSourceInputModeProvider),
    );
  }

  void begin(InstalledSkill target) {
    if (state.isBusy) return;
    state = SourceReplacementState(
      target: target,
      inputMode: ref.read(skillSourceInputModeProvider),
    );
  }

  /// Switches between the smart paste box and the typed cards, carrying what
  /// was entered across so the user does not type the Source twice.
  void selectInputMode(SkillSourceInputMode mode) {
    if (state.isBusy || mode == state.inputMode) return;
    ref.read(skillSourceInputModeProvider.notifier).select(mode);
    final draft = state.sourceDraft;
    state = state.copyWith(inputMode: mode);
    if (mode == SkillSourceInputMode.typed) {
      _invalidateSource(
        draft,
        sourceKindChosen: draft.locator.isNotEmpty ? true : null,
      );
    } else {
      updateRawInput(draft.locator);
    }
  }

  void updateRawInput(String text) {
    if (state.isBusy) return;
    final parsed = text.trim().isEmpty
        ? null
        : _parser.parse(text, mode: SkillSourceInputMode.smart);
    final current = state.sourceDraft;
    // The advanced fields outlive the paste box: a parsed ref or subpath wins,
    // otherwise what the user typed under "Advanced" stays.
    final draft = (parsed?.draft ?? const SkillSourceDraft()).copyWith(
      sourceRef: parsed?.draft.sourceRef.isNotEmpty ?? false
          ? null
          : current.sourceRef,
      repositorySubpath: parsed?.draft.repositorySubpath.isNotEmpty ?? false
          ? null
          : current.repositorySubpath,
    );
    state = state.copyWith(
      rawInput: text,
      parsed: parsed,
      clearParsed: parsed == null,
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

  void selectSourceKind(SkillSourceKind kind) {
    if (state.isBusy ||
        (state.sourceKindChosen && kind == state.sourceDraft.kind)) {
      return;
    }
    _invalidateSource(
      state.sourceDraft.copyWith(kind: kind),
      sourceKindChosen: true,
    );
  }

  void updateLocator(String value) {
    if (state.isBusy || value == state.sourceDraft.locator) return;
    _invalidateSource(state.sourceDraft.copyWith(locator: value));
  }

  void updateSourceRef(String value) {
    if (state.isBusy || value == state.sourceDraft.sourceRef) return;
    _invalidateSource(state.sourceDraft.copyWith(sourceRef: value));
  }

  void updateRepositorySubpath(String value) {
    if (state.isBusy || value == state.sourceDraft.repositorySubpath) return;
    _invalidateSource(state.sourceDraft.copyWith(repositorySubpath: value));
  }

  Future<void> inspect() async {
    final repository = _repository;
    if (state.isBusy || repository == null) return;
    state = state.copyWith(
      step: ReplacementStep.source,
      status: ReplacementStatus.inspecting,
      clearInspection: true,
      clearSelectedSlotKey: true,
      clearFailure: true,
      warnings: const [],
    );
    try {
      var completion = await _inspectAttempt(repository, state.sourceDraft);
      if (!ref.mounted) return;
      // As in Add Skill, a pasted web address that proves to hold no Skills
      // is tried once more as a Git repository.
      if (state.inputMode == SkillSourceInputMode.smart &&
          state.detection == SkillSourceDetection.webUrl &&
          completion is WorkspaceFailed<SkillSourceInspection> &&
          shouldTryWebSourceAsGit(completion.failure)) {
        completion = await _inspectAttempt(
          repository,
          state.sourceDraft.copyWith(kind: SkillSourceKind.git),
        );
        if (!ref.mounted) return;
      }
      switch (completion) {
        case WorkspaceCompleted(:final value):
          final target = state.target;
          final match = target == null
              ? null
              : value.candidates
                    .where((candidate) => candidate.slotKey == target.slotKey)
                    .firstOrNull;
          state = state.copyWith(
            step: ReplacementStep.select,
            inspection: value,
            selectedSlotKey: match?.slotKey,
            status: ReplacementStatus.ready,
            clearProgress: true,
          );
          await _stopWatching();
        case WorkspaceFailed(:final failure):
          await _fail(failure, StackTrace.current);
        case WorkspaceCommittedPending():
          state = state.copyWith(
            status: ReplacementStatus.idle,
            clearProgress: true,
          );
          await _stopWatching();
      }
    } on Object catch (error, stackTrace) {
      await _fail(error, stackTrace);
    }
  }

  Future<WorkspaceCompletion<SkillSourceInspection>> _inspectAttempt(
    SkillAcquisitionRepository repository,
    SkillSourceDraft draft,
  ) async {
    final task = repository.inspect(draft);
    _watch(task);
    final completion = await task.completed;
    if (ref.mounted) {
      state = state.copyWith(
        warnings: _mergeWarnings(state.warnings, completion.warnings),
      );
    }
    return completion;
  }

  void selectCandidate(String slotKey) {
    if (state.step != ReplacementStep.select ||
        state.status != ReplacementStatus.ready) {
      return;
    }
    final target = state.target;
    if (target != null && slotKey != target.slotKey) return;
    state = state.copyWith(selectedSlotKey: slotKey);
  }

  void continueToReplace() {
    if (!state.canContinueToReplace) return;
    state = state.copyWith(step: ReplacementStep.replace);
    ref.read(skillOperationsViewModelProvider.notifier).clearError();
  }

  void back() {
    if (state.isBusy) return;
    switch (state.step) {
      case ReplacementStep.source:
        return;
      case ReplacementStep.select:
        state = state.copyWith(
          step: ReplacementStep.source,
          clearInspection: true,
          clearSelectedSlotKey: true,
          status: ReplacementStatus.idle,
        );
      case ReplacementStep.replace:
        state = state.copyWith(step: ReplacementStep.select);
    }
  }

  Future<ReplaceSourceOutcome?> replace() async {
    final target = state.target;
    final source = state.inspection?.source;
    final slotKey = state.selectedSlotKey;
    if (target == null || source == null || slotKey == null) return null;
    final candidate = state.inspection!.candidates.firstWhere(
      (candidate) => candidate.slotKey == slotKey,
    );
    // Replacement has no "which Skill in this Source" request field the way
    // install has `skillNames`; the Source Descriptor itself must resolve to
    // exactly one Skill, or preparation rejects it as ambiguous. `skillPath`
    // is the Descriptor's designed selector, and an inspection candidate
    // reports the very value that selects it, so the chosen candidate's
    // `skillPath` narrows the Source the user typed in step one.
    final input = SkillSourceInput(
      kind: switch (source.kind) {
        SkillSourceKind.local => WorkspaceSourceKind.local,
        SkillSourceKind.git => WorkspaceSourceKind.git,
        SkillSourceKind.wellKnown => WorkspaceSourceKind.wellKnown,
      },
      locator: source.value,
      ref: source.ref,
      repositorySubpath: source.repositorySubpath,
      skillPath: candidate.skillPath,
    );
    final outcome = await ref
        .read(skillOperationsViewModelProvider.notifier)
        .replaceSource(
          skillId: target.id,
          source: input,
          expectedRevision: ref.read(skillBrowserCatalogProvider).revision,
        );
    if (outcome == ReplaceSourceOutcome.stale && ref.mounted) {
      await ref.read(skillBrowserViewModelProvider.notifier).refresh();
    }
    return outcome;
  }

  Future<void> cancel() async {
    final cancel = _cancelActive;
    if (cancel != null) {
      await cancel();
      return;
    }
    await ref.read(skillOperationsViewModelProvider.notifier).cancelOperation();
  }

  void _invalidateSource(SkillSourceDraft draft, {bool? sourceKindChosen}) {
    state = state.copyWith(
      step: ReplacementStep.source,
      status: ReplacementStatus.idle,
      sourceDraft: draft,
      sourceKindChosen: sourceKindChosen,
      clearInspection: true,
      clearSelectedSlotKey: true,
      clearProgress: true,
      warnings: const [],
      clearFailure: true,
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

  Future<void> _fail(Object error, StackTrace stackTrace) async {
    if (!ref.mounted) return;
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(
          error,
          stackTrace,
          operationKey: SkillAcquisitionOperation.inspectSource.name,
          message: AppFailureMessage.inspectSource,
        );
    final warnings = _mergeWarnings(
      state.warnings,
      failure.warnings.whereType<WorkspaceWarning>(),
    );
    if (failure.message == AppFailureMessage.operationCancelled) {
      state = state.copyWith(
        status: ReplacementStatus.idle,
        clearProgress: true,
        clearFailure: true,
        warnings: warnings,
      );
      await _stopWatching();
      return;
    }
    state = state.copyWith(
      status: ReplacementStatus.failure,
      clearProgress: true,
      failure: failure,
      warnings: warnings,
    );
    await _stopWatching();
    if (!ref.mounted) return;
    // The wizard renders no inline failure surface, so the toast is the only
    // place this reaches the user. The typed failure stays on state for the
    // status gate that keeps the wizard on step one.
    ref
        .read(appNotificationControllerProvider.notifier)
        .publish(AppNotification.failure(failure));
  }

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
