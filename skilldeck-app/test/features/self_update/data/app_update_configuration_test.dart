import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/self_update/data/app_update_configuration.dart';

void main() {
  test('leaves updater disabled when the feed is absent', () {
    expect(loadAppUpdateConfiguration(), isNull);
  });

  test('loads a valid HTTPS appcast and six-hour default interval', () {
    final configuration = loadAppUpdateConfiguration(
      feedUrl: 'https://updates.example.com/skilldeck/stable/appcast.xml',
    );

    expect(configuration?.feedUrl.toString(), contains('appcast.xml'));
    expect(configuration?.checkInterval, skillDeckDefaultUpdateInterval);
  });

  test('accepts loopback HTTP for local smoke tests', () {
    final configuration = loadAppUpdateConfiguration(
      feedUrl: 'http://127.0.0.1:18080/appcast.xml',
      intervalMinutes: '60',
    );

    expect(configuration?.checkInterval, const Duration(hours: 1));
  });

  test('rejects credentialed, remote HTTP, and short intervals', () {
    expect(
      () => loadAppUpdateConfiguration(
        feedUrl: 'https://user:secret@example.com/appcast.xml',
      ),
      throwsFormatException,
    );
    expect(
      () => loadAppUpdateConfiguration(
        feedUrl: 'http://updates.example.com/appcast.xml',
      ),
      throwsFormatException,
    );
    expect(
      () => loadAppUpdateConfiguration(
        feedUrl: 'https://updates.example.com/appcast.xml',
        intervalMinutes: '59',
      ),
      throwsFormatException,
    );
  });
}
