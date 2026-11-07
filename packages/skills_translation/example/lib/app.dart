import 'package:flutter/cupertino.dart';
import 'package:skills_translation_example/application/translation_demo_controller.dart';
import 'package:skills_translation_example/presentation/translation_demo_screen.dart';

final class SkillsTranslationExampleApp extends StatefulWidget {
  const SkillsTranslationExampleApp({
    required this.controller,
    super.key,
  });

  final TranslationDemoController controller;

  @override
  State<SkillsTranslationExampleApp> createState() =>
      _SkillsTranslationExampleAppState();
}

final class _SkillsTranslationExampleAppState
    extends State<SkillsTranslationExampleApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoApp(
        title: 'skills_translation example',
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: Color(0xFF2868D8),
          scaffoldBackgroundColor: Color(0xFFF2F2F4),
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 14,
            ),
          ),
        ),
        home: TranslationDemoScreen(controller: widget.controller),
      );
}
