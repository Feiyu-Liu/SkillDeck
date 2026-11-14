import 'package:cupertino_ui/cupertino_ui.dart';

abstract final class SkillsColors {
  static const warningSurface = Color(0xFFFFF8F0);
  static const localSourceSurface = Color(0xFFFFF3E0);
  static const webSourceSurface = Color(0xFFEFF6FF);

  static const teal = Color(0xFF0D9488);
  static const orange = Color(0xFFD97706);
  static const purple = Color(0xFF7C3AED);
  static const blue = Color(0xFF2563EB);
  static const green = Color(0xFF059669);
  static const red = Color(0xFFDC2626);

  static const candidateAccents = <Color>[teal, orange, purple, blue, red];

  static const agentAccents = <String, Color>{
    'claude': orange,
    'cursor': blue,
    'windsurf': green,
  };
}
