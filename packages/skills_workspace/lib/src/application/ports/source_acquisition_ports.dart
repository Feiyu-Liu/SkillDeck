import '../../domain/cancellation.dart';
import '../../domain/source_descriptor.dart';
import '../source/source_acquisition_models.dart';

/// Reads ordinary local Source content without mutating the Workspace.
abstract interface class LocalSourceAcquisitionPort {
  Future<SourceAcquisitionResult<AcquiredSource>> acquireLocal(
    LocalSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  });
}

/// Reads external Git Source content through the isolated system-Git adapter.
abstract interface class GitSourceAcquisitionPort {
  Future<SourceAcquisitionResult<AcquiredSource>> acquireGit(
    GitSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  });

  Future<List<SourceAcquisitionResult<AcquiredSource>>> acquireGitBatch(
    List<SourceAcquisitionRequest> requests, {
    required CancellationToken cancellationToken,
    void Function(int index, SourceAcquisitionResult<AcquiredSource> result)?
    onResult,
  });
}

/// Reads a supported well-known Source without mutating the Workspace.
abstract interface class WellKnownSourceAcquisitionPort {
  Future<SourceAcquisitionResult<AcquiredSource>> acquireWellKnown(
    WellKnownSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  });
}
