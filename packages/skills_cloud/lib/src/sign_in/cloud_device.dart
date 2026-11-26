/// The platform a Device reports when it asks to sign in.
enum CloudDevicePlatform {
  macos('macos');

  const CloudDevicePlatform(this.wireName);

  /// The value sent as `device_platform`.
  final String wireName;
}

/// How a Device describes itself on the service's approval page.
final class CloudDevice {
  /// Trims [name] and keeps its first [maxNameLength] characters.
  ///
  /// Throws [ArgumentError] when [name] is empty after trimming.
  factory CloudDevice({
    required String name,
    required CloudDevicePlatform platform,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final runes = trimmed.runes;
    final kept = runes.length <= maxNameLength
        ? trimmed
        : String.fromCharCodes(runes.take(maxNameLength)).trimRight();
    return CloudDevice._(kept, platform);
  }

  const CloudDevice._(this.name, this.platform);

  /// The longest name sent, counted in Unicode code points.
  static const maxNameLength = 64;

  final String name;
  final CloudDevicePlatform platform;
}
