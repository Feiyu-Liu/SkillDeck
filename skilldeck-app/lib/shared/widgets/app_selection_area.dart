import 'package:flutter/cupertino.dart';

/// Lets the reader drag-select and copy the text inside [child].
///
/// Each area is its own selection, so selecting in one never extends into
/// another.
class AppSelectionArea extends StatelessWidget {
  const AppSelectionArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectableRegion(
      selectionControls: cupertinoDesktopTextSelectionHandleControls,
      contextMenuBuilder: (context, state) =>
          CupertinoAdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: state.contextMenuButtonItems,
          ),
      child: child,
    );
  }
}
