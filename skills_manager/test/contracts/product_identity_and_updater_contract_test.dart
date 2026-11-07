import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps SkillDeck identity and updater pin aligned across platforms', () {
    expect(
      _read('macos/Runner/Configs/AppInfo.xcconfig'),
      allOf(
        contains('PRODUCT_NAME = SkillDeck'),
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.feiyuliu.skilldeck'),
      ),
    );
    expect(
      _read('windows/CMakeLists.txt'),
      contains('set(BINARY_NAME "SkillDeck")'),
    );
    expect(
      _read('windows/runner/Runner.rc'),
      allOf(
        contains('VALUE "ProductName", "SkillDeck"'),
        contains('VALUE "OriginalFilename", "SkillDeck.exe"'),
        contains(
          'DSAPub                 DSAPEM                  '
          '"resources\\\\winsparkle_dsa_pub.pem"',
        ),
      ),
    );
    expect(
      _read('windows/packaging/inno/skilldeck.iss'),
      allOf(
        contains('AppId={{4B88C1CF-8933-4C84-BDCE-1980AA1C73A4}'),
        contains('PrivilegesRequired=lowest'),
        contains('DefaultDirName={localappdata}\\Programs\\SkillDeck'),
        contains('#define AppExeName "SkillDeck.exe"'),
      ),
    );
    expect(
      _read('windows/runner/resources/winsparkle_dsa_pub.pem'),
      startsWith('-----BEGIN PUBLIC KEY-----'),
    );
    expect(
      _read('pubspec.yaml'),
      allOf(
        contains('auto_updater:'),
        contains('ref: 74351247aaa93743bd1c5804de54cce4de76787b'),
        isNot(contains('desktop_updater')),
      ),
    );
    expect(_read('../.gitignore'), contains('/skills_manager/keys/'));
  });
}

String _read(String path) => File(path).readAsStringSync();
