import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _libgit2Components = <String>[
  'libgit2',
  'xdiff',
  'zlib',
  'PCRE2',
  'llhttp',
  'SHA1 collision detection',
  'RFC 6234 SHA-256',
  'wildmatch',
];

Stream<LicenseEntry> loadNativeLicenses(AssetBundle bundle) async* {
  final libgit2License = await bundle.loadString('assets/licenses/libgit2.txt');
  for (final name in _libgit2Components) {
    yield LicenseEntryWithLineBreaks(<String>[name], libgit2License);
  }
  final sqliteLicense = await bundle.loadString('assets/licenses/sqlite.txt');
  yield LicenseEntryWithLineBreaks(const <String>['SQLite'], sqliteLicense);
  for (final entry in <(String, String)>[
    ('Noto Sans SC', 'assets/licenses/noto-sans-sc.txt'),
    ('Lobe icons', 'assets/licenses/lobe-icons.txt'),
    ('next_ui (ChunUI attribution)', 'assets/licenses/next-ui-notice.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks(<String>[
      entry.$1,
    ], await bundle.loadString(entry.$2));
  }
  final ofl = await bundle.loadString('assets/licenses/ofl-1.1.txt');
  for (final entry in <(String, String)>[
    ('Inter', 'Copyright 2016 The Inter Project Authors'),
    ('JetBrains Mono', 'Copyright 2020 The JetBrains Mono Project Authors'),
    ('Space Grotesk', 'Copyright 2020 The Space Grotesk Project Authors'),
  ]) {
    yield LicenseEntryWithLineBreaks(<String>[entry.$1], '${entry.$2}\n\n$ofl');
  }
}

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() => loadNativeLicenses(rootBundle));
}
