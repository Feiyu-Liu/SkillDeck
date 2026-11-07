import 'package:flutter/cupertino.dart';

abstract final class AppSpacing {
  /// Reserved for optical corrections, not structural layout rhythm.
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = 28.0;
}

abstract final class AppSizes {
  /// Smallest supported desktop window size.
  ///
  /// The main navigation rail and the narrowest content layouts both need
  /// enough room to remain usable at the same time, so this is enforced by
  /// the native desktop window rather than only by Flutter's responsive
  /// layout.
  static const minimumWindowSize = Size(450, 500);

  static const sidebarWidth = sidebarExpandedWidth;
  static const sidebarExpandedWidth = 160.0;

  /// Narrow enough that the rail reads as a rail, wide enough that a medium
  /// icon button still fits inside the sidebar's own horizontal inset.
  static const sidebarCollapsedWidth = 44.0;
  static const sidebarResizeHandleHitWidth = 24.0;

  /// Drag progress below which the sidebar is an icon-only rail.
  static const sidebarRailThreshold = 0.38;

  /// Pointer region, measured from the window's top-left corner, that reveals
  /// the macOS window buttons while the sidebar is collapsed. The buttons
  /// themselves span x 15-69pt and y 11-25pt; the zone is deliberately larger
  /// so the pointer is inside it well before it reaches them.
  static const windowButtonsRevealArea = Size(120, 52);
  static const sidebarHorizontalPadding = 6.0;
  static const contentColumnWidth = 820.0;
  static const pageHorizontalPadding = 28.0;

  static const navItemHeight = 30.0;
  static const compactControlHeight = 26.0;

  /// Medium buttons: Skill detail actions, dialogs, and default menus.
  static const buttonHeight = 30.0;

  /// The Installed filter row and the controls that sit in or match it.
  static const controlHeight = 34.0;
  static const pageCommandBarHeight = 36.0;

  static const iconXs = 12.0;
  static const iconSm = 14.0;
  static const iconMd = 16.0;
  static const iconLg = 18.0;

  static const dragRegionHeight = 36.0;
}

abstract final class AppInsets {
  static const sidebar = EdgeInsets.fromLTRB(12, 48, 12, 24);
  static const shellContent = EdgeInsets.fromLTRB(6, 16, 16, 16);
  static const pageHorizontal = EdgeInsets.symmetric(
    horizontal: AppSizes.pageHorizontalPadding,
  );
  static const pageHeader = EdgeInsets.only(top: 16);
  static const compactControl = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: AppSpacing.md,
  );
}

/// Compatibility surface for existing layout call sites.
abstract final class AppMotion {
  static const sidebarSnapDuration = Duration(milliseconds: 260);

  /// How long a control takes to change shape in place, such as the Skill
  /// update action growing from its icon circle into a labelled capsule.
  static const controlMorphDuration = Duration(milliseconds: 220);
}

abstract final class AppLayout {
  static const sidebarWidth = AppSizes.sidebarWidth;
  static const contentColumnWidth = AppSizes.contentColumnWidth;
  static const panelRadius = AppRadii.panel;
}

abstract final class AppRadii {
  static const xs = 5.0;
  static const sm = 8.0;
  static const control = 9.0;
  static const md = 10.0;
  static const lg = 12.0;
  static const dialog = 16.0;

  static const panel = 18.0;
  static const pill = 999.0;
}

abstract final class AppDialogWidths {
  static const confirm = 480.0; // short confirmations
  static const standard = 560.0; // lists and reviews
  static const wide = 640.0; // forms and multi-step flows
}
