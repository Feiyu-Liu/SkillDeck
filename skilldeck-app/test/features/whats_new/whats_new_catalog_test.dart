import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/whats_new/whats_new_catalog.dart';

WhatsNewEntry entry(String version) => WhatsNewEntry(
  version: version,
  heroAsset: 'assets/whats_new/$version.png',
  title: (_) => version,
  body: (_) => version,
);

void main() {
  test('compares only the numeric release core', () {
    expect(compareAppVersions('1.0.9-20', '1.0.9'), 0);
    expect(compareAppVersions('1.0.9+20', '1.0.9'), 0);
    expect(compareAppVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareAppVersions('1.1', '1.1.0'), 0);
    expect(compareAppVersions('0.9.0-4', '1.0.0'), lessThan(0));
  });

  group('whatsNewFor', () {
    final catalog = [entry('1.1.0'), entry('1.2.0')];

    test('shows nothing on a fresh install', () {
      expect(
        whatsNewFor(lastSeen: null, current: '1.2.0', catalog: catalog),
        isNull,
      );
    });

    test('shows nothing once the version has been seen', () {
      expect(
        whatsNewFor(lastSeen: '1.1.0', current: '1.1.0-3', catalog: catalog),
        isNull,
      );
    });

    test('shows the version an upgrade crosses', () {
      expect(
        whatsNewFor(
          lastSeen: '1.0.9-20',
          current: '1.1.0',
          catalog: catalog,
        )?.version,
        '1.1.0',
      );
    });

    test('shows the newest of several skipped versions', () {
      expect(
        whatsNewFor(
          lastSeen: '1.0.0',
          current: '1.2.1',
          catalog: catalog,
        )?.version,
        '1.2.0',
      );
    });

    test('never shows a version newer than the running one', () {
      expect(
        whatsNewFor(lastSeen: '1.0.0', current: '1.0.9', catalog: catalog),
        isNull,
      );
    });
  });
}
