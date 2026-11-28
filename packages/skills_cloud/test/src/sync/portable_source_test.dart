import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

void main() {
  test(
    'source identity ignores only labelled device-bound values with IDs',
    () {
      final source = PortableSource.deviceBound(
        originSourceType: 'local',
        originDeviceLabel: 'Mac',
        displayLabel: 'Skill',
        originSourceId: 'a' * 64,
      );
      PortableSource changed(Map<String, Object?> fields) =>
          PortableSource.fromJson({...source.toJson(), ...fields});
      final renamed = changed({
        'originDeviceLabel': 'Renamed Mac',
        'displayLabel': 'Renamed Skill',
      });
      expect(source.sameSourceAs(renamed), isTrue);
      expect(renamed.sameSourceAs(source), isTrue);
      expect(source == renamed, isFalse);
      expect(
        source.sameSourceAs(changed({'originSourceId': 'b' * 64})),
        isFalse,
      );
      expect(
        source.sameSourceAs(changed({'originSourceType': 'adoptedSnapshot'})),
        isFalse,
      );
      final legacy = changed({'originSourceId': null});
      expect(source.sameSourceAs(legacy), isFalse);
      expect(legacy.sameSourceAs(source), isFalse);
      expect(
        legacy.sameSourceAs(PortableSource.fromJson(legacy.toJson())),
        isTrue,
      );
      expect(
        legacy.sameSourceAs(
          PortableSource.fromJson({
            ...legacy.toJson(),
            'displayLabel': 'Other',
          }),
        ),
        isFalse,
      );
      for (final remote in [
        PortableSource.git(locator: 'https://example.com/repo'),
        PortableSource.wellKnown(locator: 'https://example.com/index'),
      ]) {
        expect(source.sameSourceAs(remote), isFalse);
        expect(
          remote.sameSourceAs(PortableSource.fromJson(remote.toJson())),
          isTrue,
        );
        expect(
          remote.sameSourceAs(
            PortableSource.fromJson({
              ...remote.toJson(),
              'locator': 'https://other.example/repo',
            }),
          ),
          isFalse,
        );
      }
    },
  );

  test('Device-Bound labels fit the Workspace Synced Origin domain', () {
    final maxLength = '⭐' * 256;
    final boundary = PortableSource.deviceBound(
      originSourceType: 'local',
      originDeviceLabel: '☀️ Mac',
      displayLabel: maxLength,
    );
    expect(PortableSource.fromJson(boundary.toJson()), boundary);
    for (final label in [
      '$maxLength⭐',
      'control\u007f',
      'control\u009f',
      'control\u001f',
      'root/part',
      r'root\part',
      'C:drive',
    ]) {
      expect(
        () => PortableSource.fromJson({
          ...boundary.toJson(),
          'displayLabel': label,
        }),
        throwsArgumentError,
      );
    }
  });

  test('opaque source identity distinguishes equal labels and legacy sources round-trip', () {
    final old = PortableSource.deviceBound(
      originSourceType: 'local',
      originDeviceLabel: 'Mac',
      displayLabel: 'skills',
    );
    final next = PortableSource.fromJson({
      ...old.toJson(),
      'originSourceId': 'a' * 64,
    });
    expect(old.toJson(), isNot(contains('originSourceId')));
    expect(PortableSource.fromJson(old.toJson()), old);
    expect(PortableSource.fromJson(next.toJson()), next);
    expect(next, isNot(old));
    expect(
      () => PortableSource.fromJson({
        ...old.toJson(),
        'originSourceId': '/tmp/source',
      }),
      throwsArgumentError,
    );
  });
}
