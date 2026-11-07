import '../../application/ports/activation_mutation_ports.dart';
import '../workspace_layout.dart';

/// Keeps physical Workspace layout out of application and platform modules.
final class WorkspaceActivationMaterializationPaths
    implements ActivationMaterializationPathPort {
  const WorkspaceActivationMaterializationPaths({
    required WorkspaceLayout layout,
  }) : _layout = layout;

  final WorkspaceLayout _layout;

  @override
  String repositoryCopyPath(String slotKey) =>
      _layout.repositoryCopyPath(slotKey);
}
