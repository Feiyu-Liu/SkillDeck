import '../domain/slot_key.dart';
import 'result.dart';

/// Derives the portable, Agent-visible filesystem address for a Skill name.
SkillsResult<String> deriveSlotKey(String declaredName) {
  final derivation = deriveSlotKeyValue(declaredName);
  final slotKey = derivation.value;
  if (slotKey != null) {
    return SkillsSuccess<String>(value: slotKey);
  }
  return SkillsFailure<String>(
    code: SkillsErrorCode.unsupportedSkillName,
    context: {'field': 'name', 'reason': ?derivation.rejectionReason},
  );
}
