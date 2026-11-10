import 'dart:ui';

import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// The fixed colors a Personal Tag can take, stored as `#RRGGBB`.
const personalTagPalette = <String>[
  '#8E8E93',
  '#E5484D',
  '#F76B15',
  '#D9A400',
  '#30A46C',
  '#12A594',
  '#3E63DD',
  '#8E4EC6',
];

/// Untagged or unrecognized colors render as the neutral first swatch.
Color personalTagColor(String? hex) {
  final value = hex == null || hex.length != 7
      ? null
      : int.tryParse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | (value ?? 0x8E8E93));
}

/// Picks the least-used palette color so new tags stay visually distinct.
String nextPersonalTagColor(Iterable<WorkspacePersonalTag> tags) {
  final usage = {for (final color in personalTagPalette) color: 0};
  for (final tag in tags) {
    final color = tag.color?.toUpperCase();
    if (usage.containsKey(color)) usage[color!] = usage[color]! + 1;
  }
  // Skip the neutral gray so a fresh tag gets a real hue first.
  return personalTagPalette
      .skip(1)
      .reduce((best, color) => usage[color]! < usage[best]! ? color : best);
}
