import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/l10n/generated/app_localizations_zh.dart';

void main() {
  test('uses Skill terminology throughout Chinese localization', () {
    final arb = File('lib/l10n/app_zh.arb').readAsStringSync();
    final l10n = AppLocalizationsZh();

    expect(arb, isNot(contains('技能')));
    expect(l10n.browserAddSkills, '添加 Skill');
    expect(l10n.workspaceBackToSkills, '返回 Skills 列表');
    expect(l10n.acquisitionInstall(1, ''), '安装 1 个 Skill');
    expect(l10n.acquisitionInstall(2, 's'), '安装 2 个 Skills');
  });
}
