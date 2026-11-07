import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  test('DestructiveIntent remains bound to the reviewed revision', () {
    final intent = DestructiveIntent(reviewedRevision: RepositoryRevision(42));

    expect(intent.reviewedRevision, RepositoryRevision(42));
    expect(intent, DestructiveIntent(reviewedRevision: RepositoryRevision(42)));
    expect(
      intent,
      isNot(DestructiveIntent(reviewedRevision: RepositoryRevision(43))),
    );
  });
}
