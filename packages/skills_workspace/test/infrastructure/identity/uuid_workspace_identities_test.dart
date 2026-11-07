import 'package:skills_workspace/src/infrastructure/identity/uuid_workspace_identities.dart';
import 'package:test/test.dart';

void main() {
  test('allocates distinct canonical identities for every Workspace role', () {
    const identities = UuidWorkspaceIdentities();
    final values = <String>{
      identities.allocateOperationId().value,
      identities.allocateManagedSkillId().value,
      identities.allocateSourceLineage().encoded,
      identities.allocateActivationId(),
      identities.allocateOperationSubjectId(),
    };

    expect(values, hasLength(5));
    expect(
      values,
      everyElement(
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      ),
    );
  });
}
