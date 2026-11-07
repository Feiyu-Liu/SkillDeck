import 'skill_drift_recovery_harness.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    throw ArgumentError('Expected fixture root and optional resolution.');
  }
  if (arguments.length == 2 && arguments[1] == 'keep') {
    await runSkillDriftKeepRecovery(
      root: arguments.first,
      crashAfterCommit: true,
    );
  } else {
    await runSkillDriftRestoreRecovery(
      root: arguments.first,
      crashAfterCommit: true,
    );
  }
  throw StateError('The business commit crash was not reached.');
}
