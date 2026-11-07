import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';

final class DriftExportInspector implements PublishedArtifactInspectorPort {
  DriftExportInspector({required this.delegate, this.onObserve, this.fixed});

  final PublishedArtifactInspectorPort delegate;
  final Future<void> Function(String path, int call)? onObserve;
  final PublishedArtifactInspection? fixed;
  var calls = 0;
  final List<CancellationToken> observedTokens = [];

  @override
  Future<PublishedArtifactInspection> observeMetadata({
    required String path,
    required CancellationToken cancellationToken,
  }) {
    observedTokens.add(cancellationToken);
    return delegate.observeMetadata(
      path: path,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<PublishedArtifactInspection> observe({
    required String path,
    required CancellationToken cancellationToken,
  }) async {
    observedTokens.add(cancellationToken);
    await onObserve?.call(path, ++calls);
    return fixed ??
        await delegate.observe(
          path: path,
          cancellationToken: cancellationToken,
        );
  }

  @override
  Future<PublishedArtifactInspection> inspectDirectory({
    required String path,
    required String expectedContentHash,
    required CancellationToken cancellationToken,
  }) {
    observedTokens.add(cancellationToken);
    return delegate.inspectDirectory(
      path: path,
      expectedContentHash: expectedContentHash,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<PublishedArtifactInspection> inspectSymbolicLink({
    required String path,
    required String expectedTarget,
    required CancellationToken cancellationToken,
  }) {
    observedTokens.add(cancellationToken);
    return delegate.inspectSymbolicLink(
      path: path,
      expectedTarget: expectedTarget,
      cancellationToken: cancellationToken,
    );
  }
}
