import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:url_launcher/url_launcher.dart';

final skillSourceLinkOpenerProvider = Provider<SkillSourceLinkOpener>(
  (ref) => const SkillSourceLinkOpener(),
);

class SkillSourceLinkOpener {
  const SkillSourceLinkOpener();

  Future<bool> open(SkillSourceLink link) async {
    final uri = link.uri;
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // Platform exceptions can contain the original URL. Do not log them.
      return false;
    }
  }
}
