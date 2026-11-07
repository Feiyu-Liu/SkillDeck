import 'dart:convert';

import '../../domain/source_descriptor.dart';

final class SourceDescriptorCodecException implements Exception {
  const SourceDescriptorCodecException(this.reason);

  final String reason;

  @override
  String toString() => 'SourceDescriptorCodecException($reason)';
}

final class EncodedSourceDescriptor {
  const EncodedSourceDescriptor({
    required this.kind,
    required this.payloadSchemaVersion,
    required this.payloadJson,
  });

  final String kind;
  final int payloadSchemaVersion;
  final String payloadJson;
}

/// Current-only persistence codec for credential-free Source provenance.
///
/// Historical payload codecs belong to schema migration code. Normal reads
/// deliberately reject versions other than v1 instead of guessing.
final class SourceDescriptorCodec {
  const SourceDescriptorCodec();

  static const int currentPayloadSchemaVersion = 1;

  EncodedSourceDescriptor encode(SourceDescriptor source) {
    final payload = switch (source) {
      LocalSourceDescriptor(:final locator, :final skillPath) => {
        'locator': locator,
        'skillPath': skillPath,
      },
      GitSourceDescriptor(
        :final locator,
        :final ref,
        :final repositorySubpath,
        :final skillPath,
      ) =>
        {
          'locator': _credentialFreeGitLocator(locator),
          'ref': ref,
          'repositorySubpath': repositorySubpath,
          'skillPath': skillPath,
        },
      WellKnownSourceDescriptor(:final locator, :final skillPath) => {
        'locator': _credentialFreeHttpLocator(locator),
        'skillPath': skillPath,
      },
      AdoptedSnapshotSourceDescriptor(
        :final authoritativeLocation,
        :final contentHash,
      ) =>
        {
          'authoritativeLocation': authoritativeLocation,
          'contentHash': contentHash,
        },
    };
    return EncodedSourceDescriptor(
      kind: source.type.name,
      payloadSchemaVersion: currentPayloadSchemaVersion,
      payloadJson: jsonEncode(payload),
    );
  }

  SourceDescriptor decode({
    required String kind,
    required int payloadSchemaVersion,
    required String payloadJson,
  }) {
    if (payloadSchemaVersion != currentPayloadSchemaVersion) {
      throw const SourceDescriptorCodecException(
        'unsupportedPayloadSchemaVersion',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } on FormatException {
      throw const SourceDescriptorCodecException('invalidJson');
    }
    if (decoded is! Map<String, Object?>) {
      throw const SourceDescriptorCodecException('invalidPayloadShape');
    }
    try {
      return switch (kind) {
        'local' => LocalSourceDescriptor(
          locator: _requiredString(decoded, 'locator'),
          skillPath: _stringOrDefault(decoded, 'skillPath'),
        ),
        'git' => GitSourceDescriptor(
          locator: _credentialFreeGitLocator(
            _requiredString(decoded, 'locator'),
          ),
          ref: _optionalString(decoded, 'ref'),
          repositorySubpath: _stringOrDefault(decoded, 'repositorySubpath'),
          skillPath: _stringOrDefault(decoded, 'skillPath'),
        ),
        'wellKnown' => WellKnownSourceDescriptor(
          locator: _credentialFreeHttpLocator(
            _requiredString(decoded, 'locator'),
          ),
          skillPath: _stringOrDefault(decoded, 'skillPath'),
        ),
        'adoptedSnapshot' => AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: _requiredString(
            decoded,
            'authoritativeLocation',
          ),
          contentHash: _requiredString(decoded, 'contentHash'),
        ),
        _ => throw const SourceDescriptorCodecException('unsupportedKind'),
      };
    } on SourceDescriptorCodecException {
      rethrow;
    } on ArgumentError {
      throw const SourceDescriptorCodecException('invalidPayloadValue');
    }
  }
}

String _requiredString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String || value.trim().isEmpty) {
    throw const SourceDescriptorCodecException('missingRequiredField');
  }
  return value;
}

String? _optionalString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const SourceDescriptorCodecException('invalidOptionalField');
  }
  return value;
}

String _stringOrDefault(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) return '';
  if (value is! String) {
    throw const SourceDescriptorCodecException('invalidOptionalField');
  }
  return value;
}

String _credentialFreeGitLocator(String locator) {
  final uri = Uri.tryParse(locator);
  if (uri != null && uri.hasScheme && uri.userInfo.isNotEmpty) {
    final isSshUsername =
        (uri.scheme == 'ssh' || uri.scheme == 'git+ssh') &&
        !uri.userInfo.contains(':');
    if (!isSshUsername) {
      throw const SourceDescriptorCodecException('credentialBearingLocator');
    }
  }
  return locator;
}

String _credentialFreeHttpLocator(String locator) {
  final uri = Uri.tryParse(locator);
  if (uri != null && uri.hasScheme && uri.userInfo.isNotEmpty) {
    throw const SourceDescriptorCodecException('credentialBearingLocator');
  }
  return locator;
}
