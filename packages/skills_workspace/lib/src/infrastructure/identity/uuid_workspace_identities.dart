import 'package:uuid/uuid.dart';

import '../../application/operations/operation_models.dart';
import '../../application/ports/activation_mutation_ports.dart';
import '../../application/ports/initial_import_ports.dart';
import '../../application/ports/operation_ports.dart';
import '../../domain/identifiers.dart';

/// The one infrastructure identity source for Workspace business entities.
///
/// Domain and application code observe only opaque typed IDs or canonical UUID
/// strings; the UUID package remains confined to this adapter.
final class UuidWorkspaceIdentities
    implements
        WorkspaceEntityIdentityPort,
        ActivationIdentityPort,
        OperationSubjectIdentityPort {
  const UuidWorkspaceIdentities({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  OperationId allocateOperationId() => OperationId(_uuid.v4());

  @override
  ManagedSkillId allocateManagedSkillId() => ManagedSkillId(_uuid.v4());

  @override
  SourceLineageReference allocateSourceLineage() =>
      SourceLineageReference(_uuid.v4());

  @override
  String allocateActivationId() => _uuid.v4();

  @override
  String allocateOperationSubjectId() => _uuid.v4();
}
