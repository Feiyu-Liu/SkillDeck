import 'dart:convert';

/// Compares local intent payloads; this is not a server wire digest contract.
String canonicalPayload(Object? value) => jsonEncode(_sorted(value));
Object? _sorted(Object? value) => switch (value) {
  Map<String, Object?>() => {
    for (final key in value.keys.toList()..sort()) key: _sorted(value[key]),
  },
  List<Object?>() => value.map(_sorted).toList(),
  _ => value,
};
