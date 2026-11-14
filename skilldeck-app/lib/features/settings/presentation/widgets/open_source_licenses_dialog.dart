import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/presentation/view_models/open_source_licenses.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';
import 'package:skills_manager/shared/widgets/app_selection_area.dart';

/// Opens the open source licenses dialog over the whole window.
Future<void> showOpenSourceLicensesDialog(BuildContext context) =>
    AppDialogMotion.show<void>(
      context: context,
      builder: (_) => const OpenSourceLicensesDialog(),
    );

/// The components SkillDeck ships and their license texts.
///
/// It opens on the list of components. Choosing one replaces the dialog's
/// content with that component's license texts; Back and Esc return to the
/// list, and Esc on the list closes the dialog.
class OpenSourceLicensesDialog extends ConsumerStatefulWidget {
  const OpenSourceLicensesDialog({super.key});

  @override
  ConsumerState<OpenSourceLicensesDialog> createState() =>
      _OpenSourceLicensesDialogState();
}

class _OpenSourceLicensesDialogState
    extends ConsumerState<OpenSourceLicensesDialog> {
  // The dialog's horizontal inset, matched by rows that paint their own
  // hover fill edge to edge.
  static const _horizontal = 28.0;

  OpenSourceLicensePackage? _selected;

  void _close() => Navigator.of(context).pop();

  void _showList() => setState(() => _selected = null);

  void _show(OpenSourceLicensePackage package) =>
      setState(() => _selected = package);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = _selected;
    if (selected == null) {
      final packages = ref.watch(openSourceLicensesProvider);
      return AppDialogScaffold(
        key: const Key('open-source-licenses-dialog'),
        width: AppDialogWidths.standard,
        onEscape: _close,
        header: AppDialogHeader(
          icon: LucideIcons.scale,
          title: l10n.openSourceLicensesTitle,
          subtitle: l10n.openSourceLicensesSubtitle,
          actions: [
            appDialogCloseButton(
              context,
              key: const Key('open-source-licenses-close'),
              onPressed: _close,
            ),
          ],
        ),
        sections: [
          AppDialogSection(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: switch (packages) {
              AsyncData(:final value) => Column(
                key: const Key('open-source-licenses-list'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final package in value)
                    _PackageRow(
                      key: ValueKey('open-source-license-${package.name}'),
                      package: package,
                      horizontal: _horizontal,
                      onTap: () => _show(package),
                    ),
                ],
              ),
              AsyncError() => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _horizontal,
                  vertical: AppSpacing.md,
                ),
                child: AppDialogNote(
                  tone: AppDialogTone.danger,
                  text: l10n.openSourceLicensesLoadFailed,
                ),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            },
          ),
        ],
      );
    }
    return AppDialogScaffold(
      key: const Key('open-source-license-detail'),
      width: AppDialogWidths.standard,
      onEscape: _showList,
      header: AppDialogHeader(
        title: selected.name,
        titleKey: const Key('open-source-license-title'),
        subtitle: l10n.openSourceLicensesCount(selected.licenses.length),
        actions: [
          AppIconButton(
            key: const Key('open-source-licenses-back'),
            icon: LucideIcons.arrowLeft,
            tooltip: l10n.commonBack,
            style: NeoButtonVariant.ghost,
            foregroundColor: AppPalette.of(context).textSecondary,
            onPressed: _showList,
          ),
          appDialogCloseButton(
            context,
            key: const Key('open-source-licenses-close'),
            onPressed: _close,
          ),
        ],
      ),
      sections: [
        for (final license in selected.licenses)
          AppDialogSection(
            padding: const EdgeInsets.symmetric(
              horizontal: _horizontal,
              vertical: AppSpacing.xl,
            ),
            child: _LicenseText(license: license),
          ),
      ],
    );
  }
}

/// One component in the list: its name, how many license texts name it when
/// there are several, and a chevron into them.
class _PackageRow extends StatefulWidget {
  const _PackageRow({
    required this.package,
    required this.horizontal,
    required this.onTap,
    super.key,
  });

  final OpenSourceLicensePackage package;
  final double horizontal;
  final VoidCallback onTap;

  @override
  State<_PackageRow> createState() => _PackageRowState();
}

class _PackageRowState extends State<_PackageRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final count = widget.package.licenses.length;
    return Semantics(
      button: true,
      label: widget.package.name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ColoredBox(
            color: _hovered ? colors.surfaceMuted : colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.horizontal,
                vertical: AppSpacing.sm + 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.package.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count > 1) ...[
                    Text(
                      context.l10n.openSourceLicensesCount(count),
                      style: AppTypography.of(context).caption,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Icon(
                    LucideIcons.chevronRight,
                    size: AppSizes.iconSm,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One license text, laid out paragraph by paragraph with the indentation
/// the registry recorded, in a monospace face so tables and notices keep
/// their alignment. The text can be selected and copied.
class _LicenseText extends StatefulWidget {
  const _LicenseText({required this.license});

  final LicenseEntry license;

  @override
  State<_LicenseText> createState() => _LicenseTextState();
}

class _LicenseTextState extends State<_LicenseText> {
  static const _indentWidth = 16.0;

  // Parsing the paragraphs walks the whole text; do it once per entry.
  late final List<LicenseParagraph> _paragraphs = widget.license.paragraphs
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.of(context).mono
        .copyWith(fontSize: 12, height: 1.55);
    return AppSelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, paragraph) in _paragraphs.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            if (paragraph.indent == LicenseParagraph.centeredIndent)
              Text(paragraph.text, textAlign: TextAlign.center, style: style)
            else
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: paragraph.indent * _indentWidth,
                ),
                child: Text(paragraph.text, style: style),
              ),
          ],
        ],
      ),
    );
  }
}
