import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class AppPageContent extends StatelessWidget {
  const AppPageContent({required this.child, this.contentKey, super.key});

  final Widget child;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppInsets.pageHorizontal,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: contentKey,
          constraints: const BoxConstraints(
            maxWidth: AppSizes.contentColumnWidth,
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class AppPageSliverContent extends StatelessWidget {
  const AppPageSliverContent({required this.sliver, super.key});

  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final horizontalInset = math.max(
          AppSizes.pageHorizontalPadding,
          (constraints.crossAxisExtent - AppSizes.contentColumnWidth) / 2,
        );
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset),
          sliver: sliver,
        );
      },
    );
  }
}
