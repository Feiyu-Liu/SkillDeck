const skillDeckPackageId = 'com.feiyuliu.skilldeck';
const skillDeckDefaultUpdateInterval = Duration(hours: 6);

final class AppUpdateConfiguration {
  const AppUpdateConfiguration({
    required this.feedUrl,
    this.checkInterval = skillDeckDefaultUpdateInterval,
  });

  final Uri feedUrl;
  final Duration checkInterval;
}

AppUpdateConfiguration? loadAppUpdateConfiguration({
  String feedUrl = const String.fromEnvironment('SKILLDECK_UPDATE_FEED_URL'),
  String intervalMinutes = const String.fromEnvironment(
    'SKILLDECK_UPDATE_INTERVAL_MINUTES',
    defaultValue: '360',
  ),
}) {
  final normalizedUrl = feedUrl.trim();
  final normalizedInterval = intervalMinutes.trim();
  if (normalizedUrl.isEmpty) return null;
  final interval = int.tryParse(normalizedInterval);
  if (interval == null || interval < 60) {
    throw const FormatException(
      'The update check interval must be at least 60 minutes.',
    );
  }

  final uri = Uri.tryParse(normalizedUrl);
  if (uri == null || !_isAllowedArchiveUrl(uri)) {
    throw const FormatException(
      'The update archive URL must use HTTPS or loopback HTTP.',
    );
  }

  return AppUpdateConfiguration(
    feedUrl: uri,
    checkInterval: Duration(minutes: interval),
  );
}

bool _isAllowedArchiveUrl(Uri uri) {
  if (!uri.hasScheme || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  return uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host == '::1';
}
