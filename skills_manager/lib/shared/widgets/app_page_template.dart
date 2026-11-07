import 'package:flutter/cupertino.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_frame.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';

class AppPageTemplate extends StatelessWidget {
  const AppPageTemplate({
    required this.controller,
    required this.breadcrumb,
    required this.breadcrumbIcon,
    required this.title,
    required this.slivers,
    this.headerKey,
    this.breadcrumbKey,
    this.titleKey,
    this.commandLeading,
    this.commandTrailing,
    this.titleActions,
    this.pinnedContent,
    this.pinnedContentExtent = 0,
    this.scrollViewKey,
    this.blurKey,
    super.key,
  });

  final ScrollController controller;
  final String breadcrumb;
  final IconData breadcrumbIcon;
  final String title;
  final List<Widget> slivers;
  final Key? headerKey;
  final Key? breadcrumbKey;
  final Key? titleKey;
  final Widget? commandLeading;
  final Widget? commandTrailing;
  final Widget? titleActions;
  final Widget? pinnedContent;
  final double pinnedContentExtent;
  final Key? scrollViewKey;
  final Key? blurKey;

  @override
  Widget build(BuildContext context) {
    final headerExtent = AppCollapsingHeaderMetrics.expandedExtent(
      pinnedContent == null ? 0 : pinnedContentExtent,
    );
    return AppCollapsingPageFrame(
      controller: controller,
      breadcrumb: breadcrumb,
      breadcrumbIcon: breadcrumbIcon,
      title: title,
      commandLeading: commandLeading,
      commandTrailing: commandTrailing,
      titleActions: titleActions,
      pinnedContent: pinnedContent,
      pinnedContentExtent: pinnedContentExtent,
      headerKey: headerKey,
      breadcrumbKey: breadcrumbKey,
      titleKey: titleKey,
      blurKey: blurKey,
      child: CustomScrollView(
        key: scrollViewKey,
        controller: controller,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerExtent)),
          ...slivers,
        ],
      ),
    );
  }
}
