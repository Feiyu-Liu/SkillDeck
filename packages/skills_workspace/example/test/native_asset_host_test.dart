// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:skills_workspace_example/main.dart';

void main() {
  testWidgets('Flutter host loads the package-owned Native Asset', (
    tester,
  ) async {
    final status = await tester.runAsync(verifyNativePackageLoading);
    await tester.pumpWidget(
      SkillsWorkspaceExample(status: Future<String>.value(status)),
    );
    await tester.pump();

    expect(status, 'Native revision engine ready · libgit2 1.9.7');
    expect(find.textContaining('libgit2 1.9.7'), findsOneWidget);
    expect(find.text('Derived Slot Key: example-skill'), findsOneWidget);
  });

  test('repeated native initialization remains reference-counted', () {
    final first = RevisionNativeEngine.open();
    final second = RevisionNativeEngine.open();
    try {
      expect(first.version(), const RevisionNativeVersion(1, 9, 7));
      first.close();
      expect(second.version(), const RevisionNativeVersion(1, 9, 7));
    } finally {
      first.close();
      second.close();
    }
  });
}
