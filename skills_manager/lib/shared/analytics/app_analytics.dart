import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../failures/app_failure.dart';

enum AppAnalyticsSourceKind { local, git, wellKnown }

enum AppAnalyticsScope { none, global, project }

enum WorkspaceBootstrapAnalyticsOutcome { success, recovered, failed }

enum SourceInspectionAnalyticsOutcome { success, empty, failed, cancelled }

enum SkillInstallAnalyticsOutcome {
  success,
  noChange,
  takeoverRequired,
  finalizationPending,
  failed,
  cancelled,
}

enum ExternalAdoptionAnalyticsOutcome {
  success,
  finalizationPending,

  /// Some Skills were adopted and at least one failed.
  partial,
  failed,
  cancelled,
}

final class AppAnalyticsEvent {
  const AppAnalyticsEvent._({
    required this.category,
    required this.action,
    required this.name,
    this.duration,
    this.sourceKind,
    this.scope,
    this.itemCount,
    this.targetCount,
    this.errorCode,
  });

  const AppAnalyticsEvent.appStarted()
    : this._(category: 'lifecycle', action: 'app_started', name: 'success');

  AppAnalyticsEvent.workspaceBootstrap({
    required WorkspaceBootstrapAnalyticsOutcome outcome,
    required Duration duration,
    String? errorCode,
  }) : this._(
         category: 'lifecycle',
         action: 'workspace_bootstrap',
         name: _snakeCase(outcome.name),
         duration: duration,
         errorCode: _safeCode(errorCode),
       );

  AppAnalyticsEvent.sourceInspection({
    required AppAnalyticsSourceKind sourceKind,
    required SourceInspectionAnalyticsOutcome outcome,
    required Duration duration,
    int? itemCount,
    String? errorCode,
  }) : this._(
         category: 'acquisition',
         action: 'source_inspection',
         name: _snakeCase(outcome.name),
         duration: duration,
         sourceKind: _snakeCase(sourceKind.name),
         itemCount: itemCount,
         errorCode: _safeCode(errorCode),
       );

  AppAnalyticsEvent.skillInstall({
    required AppAnalyticsSourceKind sourceKind,
    required AppAnalyticsScope scope,
    required SkillInstallAnalyticsOutcome outcome,
    required Duration duration,
    required int itemCount,
    required int targetCount,
    String? errorCode,
  }) : this._(
         category: 'acquisition',
         action: 'skill_install',
         name: _snakeCase(outcome.name),
         duration: duration,
         sourceKind: _snakeCase(sourceKind.name),
         scope: scope.name,
         itemCount: itemCount,
         targetCount: targetCount,
         errorCode: _safeCode(errorCode),
       );

  /// [itemCount] is the number of Skills selected, and [adoptedCount], sent
  /// in the target-count dimension, how many of them were adopted.
  AppAnalyticsEvent.externalAdoption({
    required ExternalAdoptionAnalyticsOutcome outcome,
    required Duration duration,
    required int itemCount,
    int? adoptedCount,
    String? errorCode,
  }) : this._(
         category: 'adoption',
         action: 'external_adoption',
         name: _snakeCase(outcome.name),
         duration: duration,
         itemCount: itemCount,
         targetCount: adoptedCount,
         errorCode: _safeCode(errorCode),
       );

  final String category;
  final String action;
  final String name;
  final Duration? duration;
  final String? sourceKind;
  final String? scope;
  final int? itemCount;
  final int? targetCount;
  final String? errorCode;

  Map<String, String> dimensions({
    required String platform,
    required String appVersion,
  }) => {
    'dimension1': platform,
    'dimension2': appVersion,
    'dimension3': ?sourceKind,
    'dimension4': ?scope,
    if (itemCount != null) 'dimension5': appAnalyticsCountBucket(itemCount!),
    if (targetCount != null)
      'dimension6': appAnalyticsCountBucket(targetCount!),
    'dimension7': ?errorCode,
  };
}

abstract interface class AppAnalytics {
  void track(AppAnalyticsEvent event);

  Future<void> setEnabled(bool enabled);

  void dispose();
}

final class NoopAppAnalytics implements AppAnalytics {
  const NoopAppAnalytics();

  @override
  void dispose() {}

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  void track(AppAnalyticsEvent event) {}
}

final appAnalyticsProvider = Provider<AppAnalytics>(
  (ref) => const NoopAppAnalytics(),
);

String appAnalyticsCountBucket(int count) => switch (count) {
  <= 0 => '0',
  1 => '1',
  <= 5 => '2_5',
  <= 10 => '6_10',
  _ => '11_plus',
};

/// Dimension 7 value: a stable code with one allowlisted reason sub-code for
/// `operationFailed` and `activationUnavailable`.
///
/// `activationUnavailable:adoptionTargetOccupied` also names what holds the
/// target, as `adoptionTargetOccupied_<occupant>`, with `other` for a value
/// outside the allowlist. Invalid Skills with source-read diagnostics append
/// one closed category; older contexts retain the coarse occupant code.
///
/// An `operationFailed` abort that the Workspace could classify
/// (`preparationFailed`, `applyFailed`, `businessCommitFailed` with an
/// allowlisted `detail`) reports `operationFailed:<reason>_<detail>`, so the
/// catch-all buckets stay separable without ever carrying free text.
/// `revisionStoreUnavailable` similarly carries an allowlisted engine failure
/// detail such as `bundleInvalid`; unknown details retain the coarse reason.
String? appAnalyticsErrorCode(AppFailure? failure) {
  if (failure == null) return null;
  final code = failure.codeKey;
  final context = failure.context;
  if (code == 'activationUnavailable') {
    final reason = context['reason'];
    if (reason is! String || !_activationUnavailableReasons.contains(reason)) {
      return code;
    }
    if (reason == 'adoptionTargetOccupied' && context.containsKey('occupant')) {
      final occupant = context['occupant'];
      if (occupant == 'invalidSkill' &&
          (context.containsKey('occupantFailureCode') ||
              context.containsKey('occupantFailureReason'))) {
        return '$code:${reason}_invalidSkill_${_adoptionFailureDetail(context)}';
      }
      return _adoptionTargetOccupants.contains(occupant)
          ? '$code:${reason}_$occupant'
          : '$code:${reason}_other';
    }
    return '$code:$reason';
  }
  if (code != 'operationFailed') return code;

  final reason = context['reason'];
  final revisionCode = context['revisionCode'];
  final value = reason is String
      ? reason
      : revisionCode is String
      ? revisionCode
      : null;
  if (_operationFailedReasons.contains(value)) {
    final detail = context['detail'];
    if (value == 'revisionStoreUnavailable' &&
        detail is String &&
        _revisionFailureDetails.contains(detail)) {
      return '$code:${value}_$detail';
    }
    if (_detailedAbortReasons.contains(value) &&
        detail is String &&
        _abortDetails.contains(detail)) {
      return '$code:${value}_$detail';
    }
    return '$code:$value';
  }
  if (!context.containsKey('reason') &&
      !context.containsKey('revisionCode') &&
      context.containsKey('operation')) {
    return '$code:uncaught';
  }
  return '$code:other';
}

/// Closed telemetry vocabulary: never interpolate source diagnostics directly.
String _adoptionFailureDetail(Map<String, Object?> context) {
  final reason = context['occupantFailureReason'];
  final detail = switch (reason) {
    'invalidFrontmatter' ||
    'invalidSkillFrontmatter' ||
    'missingName' ||
    'missingDescription' => 'frontmatter',
    'unsupportedSkillName' || 'windowsReservedDeviceName' => 'unsupportedName',
    'symbolicLinkEscapesSkillRoot' ||
    'directoryEscapesSkillRoot' => 'externalLink',
    'brokenOrCyclicSymbolicLink' ||
    'cyclicSymbolicLink' => 'brokenOrCyclicLink',
    'filesystemReadFailed' ||
    'filesystemInspectionFailed' ||
    'entryDisappearedDuringCapture' ||
    'entryChangedDuringCapture' ||
    'sourceRootNotDirectory' ||
    'searchRootUnavailable' => 'filesystem',
    'noRootSkill' || 'noValidSkills' || 'missingSkillMarkdown' => 'noRootSkill',
    _ => null,
  };
  return detail ??
      switch (context['occupantFailureCode']) {
        'contentLimitExceeded' => 'contentLimit',
        'ioFailure' || 'unavailable' => 'filesystem',
        'contentInvalid' => 'invalidContent',
        _ => 'other',
      };
}

/// Stable Revision Engine failure codes; never native diagnostics or paths.
const Set<String> _revisionFailureDetails = {
  'invalidInput',
  'storeUnavailable',
  'objectUnavailable',
  'verificationFailed',
  'bundleInvalid',
  'unexpectedFailure',
};

/// Abort reasons whose `detail` the Workspace classifies.
const Set<String> _detailedAbortReasons = {
  'preparationFailed',
  'applyFailed',
  'businessCommitFailed',
};

/// Mirrors the Workspace's `OperationAbortDetail`.
const Set<String> _abortDetails = {
  'recoveryConflict',
  'recoveryEvidence',
  'planInvariant',
  'filesystem',
  'unknown',
};

/// Reasons the Workspace attaches to `activationUnavailable`.
const Set<String> _activationUnavailableReasons = {
  'adoptionTargetOccupied',
  'activationTargetsCollide',
  'locationNotWritable',
  'locationUnavailable',
  'targetNotReplaceable',
  'targetNotSafelyReplaceable',
  'targetUnreadable',
  'unsupportedTargetType',
};

/// Mirrors the Workspace's adoption target occupants.
const Set<String> _adoptionTargetOccupants = {
  'emptyDirectory',
  'danglingLink',
  'file',
  'invalidSkill',
  'directoryWithContent',
  'otherSkill',
  'sameSlotSkill',
  'link',
  'unknown',
};

const Set<String> _operationFailedReasons = {
  'envelopeRevisionMismatch',
  'duplicateManagedSkill',
  'candidateRecoveryReferenceMismatch',
  'incompleteBatch',
  'candidateIdentityMismatch',
  'preparationFailed',
  'applyFailed',
  'businessCommitFailed',
  'invalidInstallTakeoverDraft',
  'revisionStoreUnavailable',
  'contentRejected',
  'recoveryEvidenceFailed',
  'ioFailure',
};

String _snakeCase(String value) => value.replaceAllMapped(
  RegExp(r'(?<=[a-z0-9])[A-Z]'),
  (match) => '_${match.group(0)!.toLowerCase()}',
);

String? _safeCode(String? value) {
  if (value == null || value.isEmpty) return null;
  return RegExp(r'^[a-zA-Z0-9_]+(:[a-zA-Z0-9_]+)?$').hasMatch(value)
      ? value
      : 'unexpected';
}
