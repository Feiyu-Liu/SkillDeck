import 'package:skills_workspace/src/application/ports/source_acquisition_ports.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';

typedef SourceAcquisitionHandler =
    Future<SourceAcquisitionResult<AcquiredSource>> Function(
      SourceDescriptor source,
      Set<String> selectedSkillNames,
      SourceAcquisitionOptions options,
      CancellationToken cancellationToken,
    );

final class FakeSourceAcquisitionPorts
    implements
        LocalSourceAcquisitionPort,
        GitSourceAcquisitionPort,
        WellKnownSourceAcquisitionPort {
  FakeSourceAcquisitionPorts(this.handler);

  final SourceAcquisitionHandler handler;
  final calls = <SourceDescriptor>[];
  Set<String>? lastSelection;

  Future<SourceAcquisitionResult<AcquiredSource>> _acquire(
    SourceDescriptor source,
    Set<String> selectedSkillNames,
    SourceAcquisitionOptions options,
    CancellationToken cancellationToken,
  ) {
    calls.add(source);
    lastSelection = selectedSkillNames;
    return handler(source, selectedSkillNames, options, cancellationToken);
  }

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireLocal(
    LocalSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _acquire(source, selectedSkillNames, options, cancellationToken);

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireGit(
    GitSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _acquire(source, selectedSkillNames, options, cancellationToken);

  @override
  Future<List<SourceAcquisitionResult<AcquiredSource>>> acquireGitBatch(
    List<SourceAcquisitionRequest> requests, {
    required CancellationToken cancellationToken,
    void Function(int index, SourceAcquisitionResult<AcquiredSource> result)?
    onResult,
  }) async {
    final results = <SourceAcquisitionResult<AcquiredSource>>[];
    for (var index = 0; index < requests.length; index += 1) {
      final request = requests[index];
      final result = await _acquire(
        request.source,
        request.selectedSkillNames,
        request.options,
        cancellationToken,
      );
      results.add(result);
      onResult?.call(index, result);
    }
    return results;
  }

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireWellKnown(
    WellKnownSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _acquire(source, selectedSkillNames, options, cancellationToken);
}
