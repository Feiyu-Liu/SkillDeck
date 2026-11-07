import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';
import '../../domain/source_descriptor.dart';
import '../ports/source_acquisition_ports.dart';
import 'source_acquisition_models.dart';

/// Routes Source reads without exposing transport or filesystem adapters.
///
/// This coordinator performs no Workspace writes. Duplicate Slot validation is
/// deliberately applied to every Source type at the shared boundary.
final class SourceAcquisitionCoordinator {
  const SourceAcquisitionCoordinator({
    required LocalSourceAcquisitionPort local,
    required GitSourceAcquisitionPort git,
    required WellKnownSourceAcquisitionPort wellKnown,
  }) : _local = local,
       _git = git,
       _wellKnown = wellKnown;

  final LocalSourceAcquisitionPort _local;
  final GitSourceAcquisitionPort _git;
  final WellKnownSourceAcquisitionPort _wellKnown;

  Future<SourceAcquisitionResult<SourceInspection>> inspect({
    required SourceDescriptor source,
    required SourceAcquisitionOptions options,
    CancellationToken? cancellationToken,
  }) async {
    final result = await acquire(
      source: source,
      selectedSkillNames: const <String>{},
      options: options,
      cancellationToken: cancellationToken,
    );
    final acquired = result.valueOrNull;
    if (acquired == null) {
      return copySourceAcquisitionFailure<AcquiredSource, SourceInspection>(
        result.failureOrNull!,
      );
    }
    return SourceAcquisitionSuccess<SourceInspection>(
      value: SourceInspection(
        source: acquired.canonicalSource,
        candidates: [
          for (final skill in acquired.skills)
            SourceCandidate(
              declaredName: skill.declaredName,
              description: skill.description,
              slotKey: skill.slotKey,
              skillPath: skill.skillPath,
              contentHash: skill.tree.contentHash,
              fileCount: skill.tree.fileCount,
              byteSize: skill.tree.byteSize,
            ),
        ],
      ),
      warnings: result.warnings,
    );
  }

  Future<SourceAcquisitionResult<AcquiredSource>> acquire({
    required SourceDescriptor source,
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    if (token.isCancelled) {
      return SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.operationCancelled,
      );
    }
    final selected = Set<String>.unmodifiable(selectedSkillNames);
    final result = switch (source) {
      LocalSourceDescriptor() => _local.acquireLocal(
        source,
        selectedSkillNames: selected,
        options: options,
        cancellationToken: token,
      ),
      GitSourceDescriptor() => _git.acquireGit(
        source,
        selectedSkillNames: selected,
        options: options,
        cancellationToken: token,
      ),
      WellKnownSourceDescriptor() => _wellKnown.acquireWellKnown(
        source,
        selectedSkillNames: selected,
        options: options,
        cancellationToken: token,
      ),
      AdoptedSnapshotSourceDescriptor() =>
        Future<SourceAcquisitionResult<AcquiredSource>>.value(
          SourceAcquisitionFailure<AcquiredSource>(
            code: SourceAcquisitionFailureCode.updateUnsupported,
          ),
        ),
    };
    return _validate(await result, token);
  }

  Future<List<SourceAcquisitionResult<AcquiredSource>>> acquireBatch({
    required List<SourceAcquisitionRequest> requests,
    CancellationToken? cancellationToken,
    void Function(int index, SourceAcquisitionResult<AcquiredSource> result)?
    onResult,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final results = List<SourceAcquisitionResult<AcquiredSource>?>.filled(
      requests.length,
      null,
    );
    final gitRequests = <SourceAcquisitionRequest>[];
    final gitIndexes = <int>[];
    for (var index = 0; index < requests.length; index += 1) {
      final request = requests[index];
      if (request.source is GitSourceDescriptor) {
        gitRequests.add(request);
        gitIndexes.add(index);
        continue;
      }
      final result = await acquire(
        source: request.source,
        selectedSkillNames: request.selectedSkillNames,
        options: request.options,
        cancellationToken: token,
      );
      results[index] = result;
      onResult?.call(index, result);
    }
    if (gitRequests.isNotEmpty) {
      await _git.acquireGitBatch(
        gitRequests,
        cancellationToken: token,
        onResult: (gitIndex, raw) {
          final index = gitIndexes[gitIndex];
          final result = _validate(raw, token);
          results[index] = result;
          onResult?.call(index, result);
        },
      );
    }
    return <SourceAcquisitionResult<AcquiredSource>>[
      for (final result in results)
        result ??
            SourceAcquisitionFailure<AcquiredSource>(
              code: SourceAcquisitionFailureCode.operationCancelled,
            ),
    ];
  }

  SourceAcquisitionResult<AcquiredSource> _validate(
    SourceAcquisitionResult<AcquiredSource> completed,
    CancellationToken token,
  ) {
    final acquired = completed.valueOrNull;
    if (acquired == null) return completed;
    if (token.isCancelled) {
      return SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.operationCancelled,
        warnings: completed.warnings,
      );
    }
    if (acquired.skills.isEmpty) {
      return SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.skillNotFound,
        context: const <String, Object?>{'reason': 'noValidSkills'},
        warnings: completed.warnings,
      );
    }
    final duplicate = _duplicateSlot(acquired.skills);
    if (duplicate != null) {
      return SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.duplicateSkillSlot,
        context: <String, Object?>{
          'slotKey': duplicate,
          'reason': 'duplicateSlotsWithinSource',
        },
        warnings: completed.warnings,
      );
    }
    return completed;
  }
}

String? _duplicateSlot(List<AcquiredSourceSkill> skills) {
  final seen = <String>{};
  for (final skill in skills) {
    if (!seen.add(skill.slotKey)) return skill.slotKey;
  }
  return null;
}
