import 'dart:convert';

import '../errors.dart';
import '../http/transport.dart';
import 'codec.dart';
import 'models.dart' show CloudSourceDescriptor;

String _hash(Object? value, int length) {
  if (value is! String ||
      value.length != length ||
      !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

/// One retained published event; equal revision/content does not collapse events.
final class CloudPublishedEvent {
  CloudPublishedEvent.fromJson(Map<String, Object?> json)
    : eventFingerprint = _hash(json['eventFingerprint'], 64),
      revision = _hash(json['revision'], 40),
      contentHash = _hash(json['contentHash'], 64),
      kind = text(json['kind'], maximum: 32),
      publishedAtMicros = _micros(json['publishedAtMicros']) {
    if (![
      'install',
      'adopt',
      'update',
      'publishDraft',
      'publishUpdateCandidate',
      'restorePublish',
      'replaceSource',
      'resolveSkillDrift',
    ].contains(kind)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }
  final String eventFingerprint, revision, contentHash, kind;

  /// The exact decimal timestamp, independent of JavaScript number precision.
  final BigInt publishedAtMicros;
  Map<String, Object?> toJson() => {
    'eventFingerprint': eventFingerprint,
    'revision': revision,
    'kind': kind,
    'publishedAtMicros': publishedAtMicros.toString(),
    'contentHash': contentHash,
  };
  @override
  String toString() => 'CloudPublishedEvent([redacted])';
}

BigInt _micros(Object? value) {
  if (value is! String ||
      value.length > 19 ||
      !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  final result = BigInt.parse(value);
  if (result > BigInt.parse('8640000000000000000')) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return result;
}

/// The credential-free server content contract, excluding receiver-local sidecars.
final class CloudContentManifest {
  factory CloudContentManifest.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1 || json['objectFormat'] != 'sha1') {
      throw const CloudException(CloudErrorCode.protocolVersionUnsupported);
    }
    if (json.keys.toSet().difference({
      'schemaVersion',
      'objectFormat',
      'source',
      'slotKey',
      'contentHash',
      'currentUpstream',
      'currentEffective',
      'publishedHistory',
    }).isNotEmpty) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    if (utf8.encode(jsonEncode(json)).length > 1024 * 1024) {
      throw const CloudException(CloudErrorCode.responseTooLarge);
    }
    final source = CloudSourceDescriptor.fromJson(object(json['source'])),
        slot = text(json['slotKey'], maximum: 255);
    if (!RegExp(r'^[a-z0-9_][a-z0-9._-]*$').hasMatch(slot) ||
        (slot.length < 255 && RegExp(r'[.-]$').hasMatch(slot)) ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$')
            .hasMatch(slot.split('.').first.toUpperCase())) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    final history = json['publishedHistory'];
    if (history is! List<Object?> ||
        history.isEmpty ||
        history.length > 10000) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    final events =
        history
            .map((item) => CloudPublishedEvent.fromJson(object(item)))
            .toList()
          ..sort((a, b) => a.eventFingerprint.compareTo(b.eventFingerprint));
    final upstream = _hash(json['currentUpstream'], 40),
        effective = _hash(json['currentEffective'], 40);
    if (events.map((item) => item.eventFingerprint).toSet().length !=
            events.length ||
        !events.any((item) => item.revision == effective)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return CloudContentManifest._(
      source,
      slot,
      _hash(json['contentHash'], 64),
      upstream,
      effective,
      List.unmodifiable(events),
    );
  }
  CloudContentManifest._(
    this.source,
    this.slotKey,
    this.contentHash,
    this.currentUpstream,
    this.currentEffective,
    this.publishedHistory,
  );
  final CloudSourceDescriptor source;
  final String slotKey, contentHash, currentUpstream, currentEffective;
  final List<CloudPublishedEvent> publishedHistory;
  Map<String, Object?> toJson() => freezeMap({
    'schemaVersion': 1,
    'objectFormat': 'sha1',
    'source': source.toJson(),
    'slotKey': slotKey,
    'contentHash': contentHash,
    'currentUpstream': currentUpstream,
    'currentEffective': currentEffective,
    'publishedHistory': publishedHistory.map((item) => item.toJson()).toList(),
  });
  @override
  String toString() =>
      'CloudContentManifest([redacted provenance and history])';
}

enum CloudContentStatus { ready, needsReupload }
