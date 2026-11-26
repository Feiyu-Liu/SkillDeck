void validateColor(String? color) {
  if (color != null && !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
    throw ArgumentError.value(color, 'color', 'must be a six-digit hex color');
  }
}
