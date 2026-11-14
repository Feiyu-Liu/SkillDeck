import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';

class SkillDocumentBrowserPopover extends StatefulWidget {
  const SkillDocumentBrowserPopover({
    required this.active,
    required this.documents,
    required this.catalogStatus,
    required this.selectedPath,
    required this.onSelected,
    required this.onRetryCatalog,
    this.failure,
    super.key,
  });

  final bool active;
  final List<SkillDocumentEntry> documents;
  final DocumentCatalogStatus catalogStatus;
  final String selectedPath;
  final ValueChanged<String> onSelected;
  final VoidCallback onRetryCatalog;
  final AppFailure? failure;

  @override
  State<SkillDocumentBrowserPopover> createState() =>
      _SkillDocumentBrowserPopoverState();
}

class _SkillDocumentBrowserPopoverState
    extends State<SkillDocumentBrowserPopover> {
  static const _columnWidth = 220.0;
  static const _desiredHeight = 320.0;
  static const _minimumHeight = 180.0;

  double _expandedHeight = 180;

  @override
  void initState() {
    super.initState();
    _expandedHeight = _heightForEntryCount(_rootEntryCount(widget.documents));
  }

  @override
  void didUpdateWidget(covariant SkillDocumentBrowserPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documents != widget.documents) {
      _expandedHeight = _heightForEntryCount(_rootEntryCount(widget.documents));
    }
  }

  int _rootEntryCount(Iterable<SkillDocumentEntry> documents) {
    final entries = <String>{};
    for (final document in documents) {
      entries.add(document.pathSegments.first);
    }
    return entries.length;
  }

  double _heightForEntryCount(int count) =>
      (count * 38 + 100).clamp(_minimumHeight, _desiredHeight).toDouble();

  void _handleDirectoryChanged(_DocumentDirectory directory) {
    final nextHeight = _heightForEntryCount(
      directory.directories.length + directory.documents.length,
    );
    if (nextHeight == _expandedHeight || !mounted) return;
    setState(() => _expandedHeight = nextHeight);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.selectedPath.split('/').last;
    final tooltip = context.l10n.workspaceDocumentSelectorTooltip(
      widget.selectedPath,
    );
    final textStyle = AppTypography.of(context).mono.copyWith(
      fontWeight: FontWeight.w600,
      color: AppPalette.of(context).textPrimary,
    );
    final style = SkillsButtonTheme.morphingMenuFor(context).style.copyWith(
      buttonHeight: AppSizes.controlHeight,
      panelPadding: EdgeInsets.zero,
      textStyle: textStyle,
    );
    final labelWidth = TextPainter(
      text: TextSpan(text: fileName, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final buttonWidth = (labelWidth.width + 44).clamp(120.0, 320.0);
    return SizedBox(
      width: buttonWidth,
      child: AppTooltip(
        message: tooltip,
        child: MorphingMenuButton(
          key: const Key('skill-file-picker'),
          icon: LucideIcons.fileText,
          label: fileName,
          semanticsLabel: tooltip,
          enableDragResize: false,
          enabled: widget.active,
          expandedWidth: 678,
          expandedHeight: _expandedHeight,
          direction: MorphingMenuDirection.auto,
          style: style,
          contentBuilder: (menuContext, close) => LayoutBuilder(
            builder: (context, constraints) {
              final visibleColumnCount = switch (constraints.maxWidth) {
                >= 678 => 3,
                >= 457 => 2,
                _ => 1,
              };
              return SizedBox.expand(
                key: const Key('skill-document-browser-panel'),
                child: _DocumentBrowserContent(
                  documents: widget.documents,
                  catalogStatus: widget.catalogStatus,
                  failure: widget.failure,
                  selectedPath: widget.selectedPath,
                  visibleColumnCount: visibleColumnCount,
                  onRetry: widget.onRetryCatalog,
                  onDirectoryChanged: _handleDirectoryChanged,
                  onSelected: (relativePath) {
                    widget.onSelected(relativePath);
                    close();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DocumentBrowserContent extends StatefulWidget {
  const _DocumentBrowserContent({
    required this.documents,
    required this.catalogStatus,
    this.failure,
    required this.selectedPath,
    required this.visibleColumnCount,
    required this.onRetry,
    required this.onDirectoryChanged,
    required this.onSelected,
  });

  final List<SkillDocumentEntry> documents;
  final DocumentCatalogStatus catalogStatus;
  final AppFailure? failure;
  final String selectedPath;
  final int visibleColumnCount;
  final VoidCallback onRetry;
  final ValueChanged<_DocumentDirectory> onDirectoryChanged;
  final ValueChanged<String> onSelected;

  @override
  State<_DocumentBrowserContent> createState() =>
      _DocumentBrowserContentState();
}

class _DocumentBrowserContentState extends State<_DocumentBrowserContent> {
  final ScrollController _columnScrollController = ScrollController();
  late _DocumentDirectory _root;
  late List<_DocumentDirectory> _columns;
  String? _activeDirectoryPath;

  @override
  void initState() {
    super.initState();
    _rebuildTree();
  }

  @override
  void didUpdateWidget(covariant _DocumentBrowserContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documents != widget.documents) _rebuildTree();
  }

  @override
  void dispose() {
    _columnScrollController.dispose();
    super.dispose();
  }

  void _rebuildTree() {
    _root = _DocumentDirectory.root();
    for (final document in widget.documents) {
      _root.addDocument(document);
    }
    _root.sortRecursively();
    _columns = [_root];
    _activeDirectoryPath = null;
  }

  void _openDirectory(_DocumentDirectory directory, int columnIndex) {
    setState(() {
      _activeDirectoryPath = directory.path;
      _columns
        ..removeRange(columnIndex + 1, _columns.length)
        ..add(directory);
    });
    widget.onDirectoryChanged(directory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_columnScrollController.hasClients) return;
      _columnScrollController.animateTo(
        _columnScrollController.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _goBack() {
    if (_columns.length <= 1) return;
    setState(() => _activeDirectoryPath = _columns.removeLast().path);
    widget.onDirectoryChanged(_columns.last);
  }

  void _selectDocument(String relativePath) {
    setState(() => _activeDirectoryPath = null);
    widget.onSelected(relativePath);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.workspaceDocumentBrowserTitle,
                style: AppTypography.of(context).caption.copyWith(
                  color: AppPalette.of(context).textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 1,
          child: ColoredBox(color: AppPalette.of(context).divider),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) => switch (widget.catalogStatus) {
    DocumentCatalogStatus.none || DocumentCatalogStatus.loading => Center(
      child: CupertinoActivityIndicator(
        radius: 9,
        color: AppPalette.of(context).ink,
      ),
    ),
    DocumentCatalogStatus.failure when widget.failure != null => AppFailureView(
      key: const Key('document-list-failure'),
      failure: widget.failure!,
      variant: AppFailureViewVariant.centered,
      title: context.l10n.workspaceDocumentListUnavailable,
      actionKey: const Key('retry-document-list'),
      onAction: widget.onRetry,
    ),
    DocumentCatalogStatus.failure => Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.workspaceDocumentListUnavailable,
              textAlign: TextAlign.center,
              style: AppTypography.of(context).caption,
            ),
            const SizedBox(height: 12),
            AppButton(
              key: const Key('retry-document-list'),
              label: context.l10n.commonRetry,
              icon: LucideIcons.refreshCw,
              size: NeoButtonSize.small,
              onPressed: widget.onRetry,
            ),
          ],
        ),
      ),
    ),
    DocumentCatalogStatus.ready =>
      widget.documents.isEmpty
          ? Center(
              child: Text(
                context.l10n.workspaceDocumentListEmpty,
                style: AppTypography.of(context).caption,
              ),
            )
          : widget.visibleColumnCount == 1
          ? _buildCompactColumn()
          : _buildColumns(),
  };

  Widget _buildCompactColumn() {
    final current = _columns.last;
    return Column(
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              const SizedBox(width: 4),
              if (_columns.length > 1)
                AppIconButton(
                  key: const Key('skill-document-browser-back'),
                  icon: LucideIcons.chevronLeft,
                  tooltip: CupertinoLocalizations.of(context)
                      .modalBarrierDismissLabel,
                  style: NeoButtonVariant.ghost,
                  size: 28,
                  iconSize: 15,
                  onPressed: _goBack,
                )
              else
                const SizedBox(width: 28),
              Expanded(
                child: Text(
                  current.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).caption.copyWith(
                    color: AppPalette.of(context).textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
        Expanded(
          child: _DocumentColumnBody(
            directory: current,
            selectedDirectoryPath: _activeDirectoryPath,
            selectedDocumentPath: _activeDirectoryPath == null
                ? widget.selectedPath
                : null,
            onDirectoryPressed: (directory) =>
                _openDirectory(directory, _columns.length - 1),
            onDocumentPressed: _selectDocument,
          ),
        ),
      ],
    );
  }

  Widget _buildColumns() {
    return ListView.separated(
      key: const Key('skill-document-browser-columns'),
      controller: _columnScrollController,
      scrollDirection: Axis.horizontal,
      itemCount: _columns.length,
      separatorBuilder: (context, _) => SizedBox(
        width: 1,
        child: ColoredBox(color: AppPalette.of(context).divider),
      ),
      itemBuilder: (context, index) {
        final directory = _columns[index];
        return SizedBox(
          width: _SkillDocumentBrowserPopoverState._columnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
                child: Text(
                  directory.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).caption.copyWith(
                    color: AppPalette.of(context).textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: _DocumentColumnBody(
                  directory: directory,
                  selectedDirectoryPath: _activeDirectoryPath,
                  selectedDocumentPath: _activeDirectoryPath == null
                      ? widget.selectedPath
                      : null,
                  onDirectoryPressed: (child) => _openDirectory(child, index),
                  onDocumentPressed: _selectDocument,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentColumnBody extends StatelessWidget {
  const _DocumentColumnBody({
    required this.directory,
    required this.selectedDirectoryPath,
    required this.selectedDocumentPath,
    required this.onDirectoryPressed,
    required this.onDocumentPressed,
  });

  final _DocumentDirectory directory;
  final String? selectedDirectoryPath;
  final String? selectedDocumentPath;
  final ValueChanged<_DocumentDirectory> onDirectoryPressed;
  final ValueChanged<String> onDocumentPressed;

  @override
  Widget build(BuildContext context) {
    final itemCount = directory.directories.length + directory.documents.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < directory.directories.length) {
          final child = directory.directories[index];
          return _DocumentBrowserRow(
            key: Key('skill-document-directory-${child.path}'),
            label: child.name,
            selected: selectedDirectoryPath == child.path,
            icon: const MiniFolderIcon(size: 16),
            trailing: LucideIcons.chevronRight,
            onPressed: () => onDirectoryPressed(child),
          );
        }
        final document =
            directory.documents[index - directory.directories.length];
        return _DocumentBrowserRow(
          key: Key('skill-document-file-${document.relativePath}'),
          label: document.name,
          selected: selectedDocumentPath == document.relativePath,
          icon: Icon(
            document.relativePath == 'SKILL.md'
                ? LucideIcons.fileText
                : LucideIcons.file,
            size: 15,
          ),
          onPressed: () => onDocumentPressed(document.relativePath),
        );
      },
    );
  }
}

class _DocumentBrowserRow extends StatefulWidget {
  const _DocumentBrowserRow({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onPressed,
    this.trailing,
    super.key,
  });

  final String label;
  final bool selected;
  final Widget icon;
  final IconData? trailing;
  final VoidCallback onPressed;

  @override
  State<_DocumentBrowserRow> createState() => _DocumentBrowserRowState();
}

class _DocumentBrowserRowState extends State<_DocumentBrowserRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.selected
        ? AppPalette.of(context).tooltipForeground
        : AppPalette.of(context).textPrimary;
    final background = _hovered || _focused
        ? AppPalette.of(context).surfaceMuted
        : AppPalette.of(context).transparent;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: AppCorners.smooth(
              color: widget.selected ? null : background,
              gradient: widget.selected ? AppGradients.selection : null,
              radius: AppRadii.sm,
            ),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(color: foreground),
                  child: widget.icon,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.of(context).control
                        .copyWith(color: foreground),
                  ),
                ),
                if (widget.trailing case final trailing?)
                  Icon(trailing, size: 14, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DocumentDirectory {
  _DocumentDirectory({required this.name, required this.path});

  factory _DocumentDirectory.root() =>
      _DocumentDirectory(name: 'Skill', path: '');

  final String name;
  final String path;
  final List<_DocumentDirectory> directories = [];
  final List<SkillDocumentEntry> documents = [];

  void addDocument(SkillDocumentEntry document) {
    var directory = this;
    final segments = document.pathSegments;
    for (final segment in segments.take(segments.length - 1)) {
      directory = directory._directory(segment);
    }
    directory.documents.add(document);
  }

  _DocumentDirectory _directory(String segment) {
    for (final directory in directories) {
      if (directory.name == segment) return directory;
    }
    final directoryPath = path.isEmpty ? segment : '$path/$segment';
    final directory = _DocumentDirectory(name: segment, path: directoryPath);
    directories.add(directory);
    return directory;
  }

  void sortRecursively() {
    directories.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    documents.sort((left, right) {
      if (left.relativePath == 'SKILL.md') return -1;
      if (right.relativePath == 'SKILL.md') return 1;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    for (final directory in directories) {
      directory.sortRecursively();
    }
  }
}
