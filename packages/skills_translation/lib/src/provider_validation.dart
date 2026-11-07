import 'validation.dart';

/// Validates and preserves a stable Provider identifier.
String validateProviderIdentifier(String value) {
  requireNonBlank(value, 'providerIdentifier');
  return value;
}

/// Validates and preserves a stable model identifier.
String validateModelIdentifier(String value) {
  requireNonBlank(value, 'modelIdentifier');
  return value;
}

/// Validates and normalizes an HTTP(S) API Base URI.
String validateApiBaseUri(Uri value) {
  if ((value.scheme != 'http' && value.scheme != 'https') ||
      !value.hasAuthority ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError(
      'The API Base URI must be an HTTP(S) URI without credentials, query, '
      'or fragment.',
    );
  }
  final text = value.toString();
  return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
}
