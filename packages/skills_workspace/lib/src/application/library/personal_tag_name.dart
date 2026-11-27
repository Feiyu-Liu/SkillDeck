import 'package:unorm_dart/unorm_dart.dart' as unicode;

({String displayName, String key}) normalizePersonalTagName(String value) {
  final displayName = unicode.nfc(value.trim());
  if (displayName.isEmpty || displayName.contains('\u0000')) {
    throw ArgumentError.value(value, 'name', 'must not be empty');
  }
  return (
    displayName: displayName,
    key: unicode.nfkc(displayName).toUpperCase(),
  );
}
