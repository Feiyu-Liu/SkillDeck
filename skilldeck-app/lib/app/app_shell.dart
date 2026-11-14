import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skills_manager/features/command_host/presentation/widgets/command_line_approval_sheet.dart';
import 'package:skills_manager/features/command_host/presentation/widgets/command_line_activity_overlay.dart';
import 'package:skills_manager/shared/platform/mac_window_controls.dart';
import 'package:skills_manager/shared/widgets/app_resizable_sidebar.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/external_skills_view_model.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/self_update/presentation/widgets/self_update_sidebar_button.dart';
import 'package:skills_manager/features/settings/presentation/view_models/app_settings_view_model.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/whats_new/presentation/whats_new_dialog.dart';
import 'package:skills_manager/features/whats_new/whats_new_catalog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';
import 'package:window_manager/window_manager.dart';

class SkillsManagerShell extends ConsumerStatefulWidget {
  const SkillsManagerShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<SkillsManagerShell> createState() => _SkillsManagerShellState();
}

class _SkillsManagerShellState extends ConsumerState<SkillsManagerShell> {
  /// The macOS window buttons sit on top of the shell's top-left corner. While
  /// the sidebar is a narrow rail they would crowd the content panel, so they
  /// are hidden and revealed again when the pointer approaches that corner.
  final MacWindowControls? _windowControls = Platform.isMacOS
      ? MacWindowControls()
      : null;
  double _sidebarProgress = 1;
  bool _pointerNearWindowButtons = false;
  bool _syncedInitialSidebarProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadAndScan());
      _showWhatsNew();
    });
  }

  @override
  void dispose() {
    // Never leave the window without its controls if the shell goes away.
    unawaited(_windowControls?.setVisible(true));
    super.dispose();
  }

  void _handleSidebarProgress(double progress) {
    if (progress == _sidebarProgress) return;
    _sidebarProgress = progress;
    _syncWindowButtons();
  }

  void _handlePointerPosition(PointerEvent event) {
    if (_windowControls == null) return;
    // Driven by where the pointer *is*, never by an exit event: while the
    // pointer sits on a revealed button the native view swallows the hover,
    // so an exit-driven rule would hide the button out from under it.
    const reveal = AppSizes.windowButtonsRevealArea;
    final near =
        event.position.dx <= reveal.width && event.position.dy <= reveal.height;
    if (near == _pointerNearWindowButtons) return;
    _pointerNearWindowButtons = near;
    _syncWindowButtons();
  }

  void _syncWindowButtons() {
    final controls = _windowControls;
    if (controls == null) return;
    final rail = _sidebarProgress < AppSizes.sidebarRailThreshold;
    unawaited(controls.setVisible(!rail || _pointerNearWindowButtons));
  }

  void _showWhatsNew() {
    final entry = ref.read(pendingWhatsNewProvider);
    if (entry == null || !mounted) return;
    unawaited(
      AppDialogMotion.show<void>(
        context: context,
        builder: (_) => WhatsNewDialog(entry: entry),
      ),
    );
  }

  Future<void> _loadAndScan() async {
    await ref.read(skillBrowserViewModelProvider.notifier).load();
    if (!mounted) return;
    await ref.read(externalSkillsViewModelProvider.notifier).scan();
  }

  @override
  Widget build(BuildContext context) {
    listenForCommandLineApprovals(ref);
    final updateCoordinator = ref.watch(appUpdateCoordinatorProvider);
    final settingsState = ref.watch(appSettingsViewModelProvider);
    final settingsLoaded = settingsState.status != AppSettingsStatus.loading;
    if (settingsLoaded && !_syncedInitialSidebarProgress) {
      _syncedInitialSidebarProgress = true;
      _sidebarProgress = settingsState.settings.sidebarCollapsed ? 0 : 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncWindowButtons();
      });
    }
    return CupertinoPageScaffold(
      backgroundColor: AppPalette.of(context).canvas,
      child: Listener(
        // Hover covers the idle pointer; move keeps the state honest while a
        // drag is in progress, when no hover events are delivered at all.
        onPointerHover: _handlePointerPosition,
        onPointerMove: _handlePointerPosition,
        child: AppResizableSidebar(
          key: ValueKey(settingsLoaded),
          initiallyCollapsed: settingsState.settings.sidebarCollapsed,
          onProgressChanged: _handleSidebarProgress,
          onCollapsedChanged: (collapsed) => ref
              .read(appSettingsViewModelProvider.notifier)
              .setSidebarCollapsed(collapsed),
          sidebarBuilder: (context, width, progress) => AppSidebar(
            width: width,
            progress: progress,
            selected: NavSection.values[widget.navigationShell.currentIndex],
            onSelected: (section) => widget.navigationShell.goBranch(
              section.index,
              initialLocation:
                  section.index == widget.navigationShell.currentIndex,
            ),
            updatePromptBuilder: updateCoordinator == null
                ? null
                : (rail) => SelfUpdateSidebarButton(rail: rail),
          ),
          foregroundBuilder: Platform.isMacOS
              ? (context, sidebarWidth, viewportWidth) => Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      width: sidebarWidth,
                      height: AppSizes.dragRegionHeight,
                      child: const DragToMoveArea(child: SizedBox.expand()),
                    ),
                    Positioned(
                      top: 0,
                      left: sidebarWidth + AppSizes.sidebarResizeHandleHitWidth,
                      width:
                          (viewportWidth -
                                  sidebarWidth -
                                  AppSizes.sidebarResizeHandleHitWidth)
                              .clamp(0.0, double.infinity),
                      height: AppSizes.dragRegionHeight,
                      child: const DragToMoveArea(child: SizedBox.expand()),
                    ),
                  ],
                )
              : null,
          child: Padding(
            padding: AppInsets.shellContent,
            child: DecoratedBox(
              decoration: AppCorners.smooth(
                color: AppPalette.of(context).surface,
                radius: AppRadii.panel,
                shadows: AppShadows.of(context).contentPanel,
              ),
              child: AppSmoothClip(
                radius: AppRadii.panel,
                child: ColoredBox(
                  color: AppPalette.of(context).surface,
                  child: Stack(
                    children: [
                      Positioned.fill(child: widget.navigationShell),
                      const Positioned.fill(
                        child: CommandLineActivityOverlay(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
