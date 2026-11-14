import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo_registry.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class AgentLogo extends StatelessWidget {
  const AgentLogo({
    required this.agentId,
    this.size = 20,
    this.color,
    this.useBrandColor = true,
    this.genericIconName,
    super.key,
  });

  final String agentId;
  final double size;
  final Color? color;
  final bool useBrandColor;
  final String? genericIconName;
  static const _genericIcons = <String, IconData>{
    'bot': LucideIcons.bot,
    'terminal': LucideIcons.terminal,
    'sparkles': LucideIcons.sparkles,
    'brainCircuit': LucideIcons.brainCircuit,
    'braces': LucideIcons.braces,
    'cpu': LucideIcons.cpu,
    'wandSparkles': LucideIcons.wandSparkles,
  };

  static IconData iconFor(String name) =>
      _genericIcons[name] ?? LucideIcons.bot;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? AppPalette.of(context).bodyContent;
    final monochromeAssetPath = AgentLogoRegistry.monochromeAssetPathFor(
      agentId,
    );
    final colorAssetPath = useBrandColor
        ? AgentLogoRegistry.colorAssetPathFor(agentId)
        : null;
    final assetPath = colorAssetPath ?? monochromeAssetPath;
    return SizedBox.square(
      key: Key('agent-logo-$agentId'),
      dimension: size,
      child: assetPath == null
          ? Icon(
              iconFor(genericIconName ?? agentId),
              size: size,
              color: resolvedColor,
            )
          : assetPath.endsWith('.png')
          ? Image.asset(
              assetPath,
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            )
          : SvgPicture.asset(
              assetPath,
              width: size,
              height: size,
              fit: BoxFit.contain,
              colorFilter: colorAssetPath == null
                  ? ColorFilter.mode(resolvedColor, BlendMode.srcIn)
                  : null,
              excludeFromSemantics: true,
            ),
    );
  }
}

class AgentLogoStack extends StatelessWidget {
  const AgentLogoStack({
    required this.agentIds,
    this.logoSize = 30,
    this.overlap = 12,
    this.maxVisible = 3,
    super.key,
  }) : assert(maxVisible > 0),
       assert(overlap >= 0 && overlap < logoSize);

  final Iterable<String> agentIds;
  final double logoSize;
  final double overlap;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final uniqueAgentIds = agentIds.toSet().toList(growable: false);
    if (uniqueAgentIds.isEmpty) {
      return _LogoTile(agentId: '', size: logoSize);
    }

    final hasOverflow = uniqueAgentIds.length > maxVisible;
    final visibleLogoCount = hasOverflow
        ? maxVisible - 1
        : uniqueAgentIds.length;
    final visibleAgentIds = uniqueAgentIds.take(visibleLogoCount).toList();
    final itemCount = visibleAgentIds.length + (hasOverflow ? 1 : 0);
    final width = logoSize + ((itemCount - 1) * overlap);

    return SizedBox(
      key: const Key('agent-logo-stack'),
      width: width,
      height: logoSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry in visibleAgentIds.indexed)
            Positioned(
              left: entry.$1 * overlap,
              child: _LogoTile(agentId: entry.$2, size: logoSize),
            ),
          if (hasOverflow)
            Positioned(
              left: visibleAgentIds.length * overlap,
              child: _OverflowTile(
                count: uniqueAgentIds.length - visibleAgentIds.length,
                size: logoSize,
              ),
            ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.agentId, required this.size});

  final String agentId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: AppCorners.smooth(
        color: AppPalette.of(context).surfaceMuted,
        radius: size * 0.3,
        side: BorderSide(color: AppPalette.of(context).white, width: 1.5),
      ),
      child: AgentLogo(
        agentId: agentId,
        size: size * 0.56,
        color: AppPalette.of(context).bodyContent,
      ),
    );
  }
}

class _OverflowTile extends StatelessWidget {
  const _OverflowTile({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('agent-logo-stack-overflow'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: AppCorners.smooth(
        color: AppPalette.of(context).surfaceMuted,
        radius: size * 0.3,
        side: BorderSide(color: AppPalette.of(context).white, width: 1.5),
      ),
      child: Text(
        '+$count',
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          color: AppPalette.of(context).textSecondary,
        ),
      ),
    );
  }
}
