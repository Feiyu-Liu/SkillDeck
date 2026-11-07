import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  group('deriveSlotKey', () {
    test('uses the portable CLI installation-directory convention', () {
      expect(deriveSlotKey('My Skill').valueOrNull, 'my-skill');
      expect(deriveSlotKey('foo@bar').valueOrNull, 'foo-bar');
      expect(deriveSlotKey('café').valueOrNull, 'caf');
      expect(deriveSlotKey('hello_world.v2').valueOrNull, 'hello_world.v2');
      expect(deriveSlotKey('...Hello---').valueOrNull, 'hello');
    });

    test('limits keys to 255 ASCII characters', () {
      final result = deriveSlotKey('A' * 300);

      expect(result, isA<SkillsSuccess<String>>());
      expect(result.valueOrNull, hasLength(255));
    });

    test('rejects names that collapse to empty or reserved device names', () {
      expect(
        deriveSlotKey('中文').failureOrNull?.code,
        SkillsErrorCode.unsupportedSkillName,
      );

      for (final declaredName in [
        'CON',
        'con.txt',
        'PRN',
        'AUX.md',
        'NUL',
        'COM1.skill',
        'COM9',
        'LPT1',
        'lpt9.notes',
      ]) {
        final result = deriveSlotKey(declaredName);

        expect(
          result.failureOrNull?.code,
          SkillsErrorCode.unsupportedSkillName,
          reason: declaredName,
        );
        expect(
          result.failureOrNull?.context['reason'],
          'windowsReservedDeviceName',
          reason: declaredName,
        );
      }
    });
  });
}
