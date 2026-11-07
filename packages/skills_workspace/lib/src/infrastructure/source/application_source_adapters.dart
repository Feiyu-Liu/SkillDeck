import '../../application/ports/source_acquisition_ports.dart';
import '../../application/source/source_acquisition_models.dart' as app;
import '../../domain/cancellation.dart';
import '../../domain/source_descriptor.dart';
import 'local_source.dart';
import 'source_models.dart' as infrastructure;
import 'source_result.dart' as infrastructure;
import 'well_known_source.dart';

/// Application-facing bridge over the existing ordinary-directory adapter.
final class LocalApplicationSourceAdapter
    implements LocalSourceAcquisitionPort {
  LocalApplicationSourceAdapter({LocalSourceAdapter? adapter})
    : _adapter = adapter ?? LocalSourceAdapter(followDirectoryLinks: true);

  final LocalSourceAdapter _adapter;

  @override
  Future<app.SourceAcquisitionResult<app.AcquiredSource>> acquireLocal(
    LocalSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required app.SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) async => _mapResult(
    await _adapter.acquire(
      source,
      selectedSkills: selectedSkillNames,
      options: infrastructure.SkillDiscoveryOptions(
        includeInternal: options.includeInternal,
        fullDepth: options.fullDepth,
      ),
      cancellation: _SourceCancellation(cancellationToken),
    ),
  );
}

/// Application-facing bridge over the existing well-known adapter.
final class WellKnownApplicationSourceAdapter
    implements WellKnownSourceAcquisitionPort {
  WellKnownApplicationSourceAdapter({WellKnownSourceAdapter? adapter})
    : _adapter = adapter ?? WellKnownSourceAdapter();

  final WellKnownSourceAdapter _adapter;

  @override
  Future<app.SourceAcquisitionResult<app.AcquiredSource>> acquireWellKnown(
    WellKnownSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required app.SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) async => _mapResult(
    await _adapter.acquire(
      source,
      selectedSkills: selectedSkillNames,
      options: infrastructure.SkillDiscoveryOptions(
        includeInternal: options.includeInternal,
        fullDepth: options.fullDepth,
      ),
      cancellation: _SourceCancellation(cancellationToken),
    ),
  );
}

app.SourceAcquisitionResult<app.AcquiredSource> _mapResult(
  infrastructure.SourceResult<infrastructure.AcquiredSource> result,
) {
  final acquired = result.valueOrNull;
  final warnings = result.warnings.map(_mapWarning).toList(growable: false);
  if (acquired == null) {
    final failure = result.failureOrNull!;
    return app.SourceAcquisitionFailure<app.AcquiredSource>(
      code: _mapFailure(failure),
      context: failure.context,
      warnings: warnings,
    );
  }
  return app.SourceAcquisitionSuccess<app.AcquiredSource>(
    value: app.AcquiredSource(
      canonicalSource: acquired.canonicalSource,
      resolvedSourceRevision: acquired.resolvedSourceRevision,
      skills: [for (final skill in acquired.skills) _mapSkill(skill)],
    ),
    warnings: warnings,
  );
}

app.AcquiredSourceSkill _mapSkill(infrastructure.AcquiredSourceSkill skill) =>
    app.AcquiredSourceSkill(
      provenance: skill.provenance,
      declaredName: skill.declaredName,
      description: skill.description,
      slotKey: skill.slotKey,
      skillPath: skill.skillPath,
      frontmatter: skill.frontmatter,
      tree: skill.tree,
      pluginName: skill.pluginName,
    );

app.SourceAcquisitionFailureCode _mapFailure(
  infrastructure.SourceFailure<infrastructure.AcquiredSource> failure,
) => switch (failure.code) {
  infrastructure.SourceFailureCode.cancelled =>
    app.SourceAcquisitionFailureCode.operationCancelled,
  infrastructure.SourceFailureCode.unavailable =>
    app.SourceAcquisitionFailureCode.sourceUnavailable,
  infrastructure.SourceFailureCode.rejected =>
    app.SourceAcquisitionFailureCode.transportRejected,
  infrastructure.SourceFailureCode.invalidSource
      when failure.context['reason'] == 'unsupportedSkillName' =>
    app.SourceAcquisitionFailureCode.unsupportedSkillName,
  infrastructure.SourceFailureCode.invalidSource ||
  infrastructure.SourceFailureCode.contentInvalid =>
    app.SourceAcquisitionFailureCode.invalidSkill,
  infrastructure.SourceFailureCode.notFound =>
    app.SourceAcquisitionFailureCode.skillNotFound,
  infrastructure.SourceFailureCode.httpFailure =>
    app.SourceAcquisitionFailureCode.httpFailure,
  infrastructure.SourceFailureCode.digestMismatch =>
    app.SourceAcquisitionFailureCode.digestMismatch,
  infrastructure.SourceFailureCode.archiveInvalid =>
    app.SourceAcquisitionFailureCode.archiveInvalid,
  infrastructure.SourceFailureCode.contentLimitExceeded =>
    app.SourceAcquisitionFailureCode.skillContentLimitExceeded,
  infrastructure.SourceFailureCode.ioFailure =>
    app.SourceAcquisitionFailureCode.ioFailure,
};

app.SourceAcquisitionWarning _mapWarning(
  infrastructure.SourceWarning warning,
) => app.SourceAcquisitionWarning(
  code: switch (warning.code) {
    infrastructure.SourceWarningCode.sourceEntrySkipped =>
      app.SourceAcquisitionWarningCode.sourceEntrySkipped,
  },
  context: warning.context,
);

final class _SourceCancellation
    implements infrastructure.SourceCancellationSignal {
  const _SourceCancellation(this._token);

  final CancellationToken _token;

  @override
  bool get isCancelled => _token.isCancelled;

  @override
  Future<void> get whenCancelled => _token.whenCancelled;
}
