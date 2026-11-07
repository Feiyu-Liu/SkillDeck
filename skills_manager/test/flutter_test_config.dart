import 'dart:async';

import 'package:skills_manager/shared/widgets/app_collapsing_page_frame.dart';

/// Runs before every widget test file in this directory.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The page blur's shader runs on the CPU here and costs seconds per frame.
  AppCollapsingPageFrame.blurEnabled = false;
  await testMain();
}
