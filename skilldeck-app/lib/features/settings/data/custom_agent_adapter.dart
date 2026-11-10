import 'package:skills_manager/features/settings/models/app_settings.dart';

void validateCustomAgentIds(Iterable<CustomAgentSettings> agents) {
  final ids = <String>{};
  for (final agent in agents) {
    if (!agent.id.startsWith('custom-') || !ids.add(agent.id)) {
      throw const FormatException(
        'Custom Agent ID conflicts with an existing Agent.',
      );
    }
  }
}
