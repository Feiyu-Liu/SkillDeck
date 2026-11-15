import '../errors.dart';
import '../http/transport.dart';

Map<String, Object?> object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

String text(Object? value, {int maximum = 4096}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

String identifier(Object? value) {
  final result = text(value, maximum: 256);
  if (result.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return result;
}

int integer(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

DateTime timestamp(Object? value) {
  try {
    return DateTime.fromMillisecondsSinceEpoch(integer(value), isUtc: true);
  } on CloudException {
    rethrow;
  } catch (_) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
}

bool boolean(Object? value) {
  if (value is! bool) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

Map<String, Object?> envelope(CloudResponse response) {
  final body = response.body;
  if (body['protocolVersion'] != 1) {
    throw const CloudException(CloudErrorCode.protocolVersionUnsupported);
  }
  if (response.statusCode < 200 ||
      response.statusCode >= 300 ||
      body.containsKey('error')) {
    final error = object(body['error']);
    final code = error['code'];
    final mapped = switch (code) {
      'reconciliationRequired' => CloudErrorCode.needsReconciliation,
      'retryable' => CloudErrorCode.unavailable,
      String() =>
        CloudErrorCode.values.where((item) => item.name == code).firstOrNull,
      _ => null,
    };
    throw CloudException(
      mapped ?? CloudErrorCode.unavailable,
      retryable: mapped != null && error['retryable'] == true,
    );
  }
  return object(body['data']);
}

/// A service sequence encoded exactly as a decimal string on the wire.
final class CloudSequence implements Comparable<CloudSequence> {
  /// Parses the full D1 signed 64-bit nonnegative range without JSON numbers.
  factory CloudSequence.parse(Object? value) {
    if (value is! String ||
        value.length > 19 ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    final parsed = BigInt.parse(value);
    if (parsed > BigInt.parse('9223372036854775807')) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return CloudSequence._(parsed);
  }
  CloudSequence._(this.value);

  /// The exact integer value.
  final BigInt value;

  /// The canonical decimal wire representation.
  String toJson() => value.toString();
  @override
  int compareTo(CloudSequence other) => value.compareTo(other.value);
  @override
  bool operator ==(Object other) =>
      other is CloudSequence && value == other.value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => 'CloudSequence($value)';
}
