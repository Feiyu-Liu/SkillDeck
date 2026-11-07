import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/licenses/native_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads native component license entries from bundled assets', () async {
    final entries = await loadNativeLicenses(rootBundle).toList();
    final names = entries.expand((entry) => entry.packages).toSet();
    expect(
      names,
      containsAll(<String>[
        'libgit2',
        'xdiff',
        'zlib',
        'PCRE2',
        'llhttp',
        'SHA1 collision detection',
        'RFC 6234 SHA-256',
        'wildmatch',
        'SQLite',
        'Noto Sans SC',
        'Lobe icons',
        'next_ui (ChunUI attribution)',
        'Inter',
        'JetBrains Mono',
        'Space Grotesk',
      ]),
    );
    expect(entries.every((entry) => entry.paragraphs.isNotEmpty), isTrue);
    final notice = entries
        .singleWhere(
          (entry) => entry.packages.contains('next_ui (ChunUI attribution)'),
        )
        .paragraphs
        .map((paragraph) => paragraph.text)
        .join('\n');
    expect(notice, contains('Copyright (c) 2026 liseami'));
    expect(notice, contains('Permission is hereby granted'));
    expect(notice, contains('THE SOFTWARE IS PROVIDED'));
  });
}
