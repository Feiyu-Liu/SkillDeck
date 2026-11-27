import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

void main() {
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
