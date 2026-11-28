import 'dart:convert';

import '../api/cloud_values.dart';

/// Versioned, credential-free provenance with portable source identity.
final class PortableSource {
  PortableSource.git({
    required String locator,
    String? ref,
    String repositorySubpath = '',
    String skillPath = '',
  }) : _json = {
         'version': 1,
         'type': 'git',
         'locator': locator,
         'ref': ref,
         'repositorySubpath': repositorySubpath,
         'skillPath': skillPath,
       } {
    _remote(locator);
    _relative(repositorySubpath);
    _relative(skillPath);
  }
  PortableSource.wellKnown({required String locator, String skillPath = ''})
    : _json = {
        'version': 1,
        'type': 'wellKnown',
        'locator': locator,
        'skillPath': skillPath,
      } {
    _remote(locator);
    _relative(skillPath);
  }
  PortableSource.deviceBound({
    required String originSourceType,
    required String originDeviceLabel,
    required String displayLabel,
    String? originSourceId,
  }) : _json = {
         'version': 1,
         'type': 'deviceBound',
         'originSourceType': originSourceType,
         'originDeviceLabel': originDeviceLabel,
         'displayLabel': displayLabel,
         'originSourceId': ?originSourceId,
       } {
    if (!['local', 'adoptedSnapshot'].contains(originSourceType)) {
      throw ArgumentError('Invalid origin source type');
    }
    _label(originDeviceLabel);
    _label(displayLabel);
    if (originSourceId != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(originSourceId)) {
      throw ArgumentError('Invalid portable source identity');
    }
  }
  final Map<String, Object?> _json;
  bool get isDeviceBound => _json['type'] == 'deviceBound';
  bool get isAdoptedSnapshot => _json['originSourceType'] == 'adoptedSnapshot';
  Map<String, Object?> toJson() => Map.unmodifiable(_json);
  factory PortableSource.fromJson(Map<String, Object?> m) {
    if (m['version'] != 1) throw const FormatException('source_version');
    return switch (m['type']) {
      'git' => PortableSource.git(
        locator: jsonString(m['locator']),
        ref: nullableString(m['ref']),
        repositorySubpath: jsonString(m['repositorySubpath']),
        skillPath: jsonString(m['skillPath']),
      ),
      'wellKnown' => PortableSource.wellKnown(
        locator: jsonString(m['locator']),
        skillPath: jsonString(m['skillPath']),
      ),
      'deviceBound' => PortableSource.deviceBound(
        originSourceType: jsonString(m['originSourceType']),
        originDeviceLabel: jsonString(m['originDeviceLabel']),
        displayLabel: jsonString(m['displayLabel']),
        originSourceId: nullableString(m['originSourceId']),
      ),
      _ => throw const FormatException('source_type'),
    };
  }

  /// Compares source identity without treating display labels as replacement.
  /// Legacy device-bound values without an ID retain full-value comparison.
  bool sameSourceAs(PortableSource other) {
    if (isDeviceBound &&
        other.isDeviceBound &&
        _json['originSourceId'] != null &&
        other._json['originSourceId'] != null) {
      return _json['originSourceType'] == other._json['originSourceType'] &&
          _json['originSourceId'] == other._json['originSourceId'];
    }
    return this == other;
  }

  @override
  bool operator ==(Object other) =>
      other is PortableSource && jsonEncode(_json) == jsonEncode(other._json);
  @override
  int get hashCode => jsonEncode(_json).hashCode;
}

void _label(String value) {
  if (value.trim().isEmpty ||
      value.runes.length > 256 ||
      value.contains('/') ||
      value.contains(r'\') ||
      value.contains(':') ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value)) {
    throw ArgumentError('Invalid portable source label');
  }
}

void _relative(String value) {
  if (value.startsWith('/') ||
      value.contains(r'\') ||
      value.split('/').contains('..') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    throw ArgumentError('Source path must be relative');
  }
}

void _remote(String value) {
  if (RegExp(r'^[^@/:\s]+@[^/:\s]+:[^\s]+$').hasMatch(value)) return;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['https', 'http', 'ssh', 'git'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.contains(':') ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'ssh' && uri.userInfo.isNotEmpty)) {
    throw ArgumentError('Source locator must be portable and credential-free');
  }
}
