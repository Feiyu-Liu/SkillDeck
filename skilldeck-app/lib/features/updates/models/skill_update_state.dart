import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

/// The shared, App-session lifetime update state of one managed Skill.
///
/// The four cases are explicit on purpose. An absent map entry is
/// [SkillUpdateNotChecked]; no call site may infer "never checked" from a
/// missing key. [SkillUpdateCheckFailed] (the check itself could not run) stays
/// distinct from `SkillUpdateChecked(sourceUnavailable)` (the Source was
/// reached and reported unavailable) because the two render differently.
///
/// Reports are persisted in the Workspace's external-observation cache, but
/// never reach the authoritative Workspace Snapshot, operation history, or
/// Source provenance.
sealed class SkillUpdateState {
  const SkillUpdateState();

  /// The report of a settled check, or `null` when none is known.
  WorkspaceUpdateReport? get report => null;

  /// Whether the Skill is known to have an update ready to apply.
  bool get updateAvailable =>
      report?.status == WorkspaceUpdateStatus.updateAvailable;
}

final class SkillUpdateNotChecked extends SkillUpdateState {
  const SkillUpdateNotChecked();
}

final class SkillUpdateChecking extends SkillUpdateState {
  const SkillUpdateChecking();
}

final class SkillUpdateChecked extends SkillUpdateState {
  const SkillUpdateChecked(this.report);

  @override
  final WorkspaceUpdateReport report;
}

final class SkillUpdateCheckFailed extends SkillUpdateState {
  const SkillUpdateCheckFailed(this.failure);

  final AppFailure failure;
}

/// The Snapshot-derived inputs that make a stored update report meaningful.
///
/// A report describes "this revision, acquired from this Source, in this
/// resolution state". When any of those change the report is meaningless, so
/// the basis drives both entry invalidation and the stale-write guard that
/// stops an older in-flight check from republishing an obsolete report.
final class SkillUpdateBasis {
  const SkillUpdateBasis._(this._value);

  factory SkillUpdateBasis.of(WorkspaceSkill skill) {
    final source = skill.source;
    return SkillUpdateBasis._(
      [
        source.kind.name,
        source.locator,
        source.ref ?? '',
        source.repositorySubpath,
        source.skillPath,
        skill.currentRevision.contentHash,
        skill.updateCandidate?.status.name ?? '',
        (skill.draft?.isDirty ?? false) ? 'dirty' : '',
      ].join(' '),
    );
  }

  final String _value;

  String get fingerprint => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillUpdateBasis && _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

/// Whether the Snapshot alone already proves a resolution workflow is pending.
///
/// This mirrors the package's own predicate, so the App never spends a network
/// round trip to learn something the Snapshot already carries.
bool skillRequiresUpdateResolution(WorkspaceSkill skill) =>
    skill.updateCandidate != null || (skill.draft?.isDirty ?? false);
