# SkillDeck

`skills_manager` is the Flutter desktop application package for SkillDeck on
macOS and Windows. Linux remains a supported platform for the underlying
`skills_workspace` package, but Linux is not a SkillDeck App release target.

The App owns one process-lifetime `skills_workspace` facade and one root
Snapshot pipeline. It installs from Local, Git, and Well-known Sources; manages
global and Project Activations; adopts existing Agent Skills; checks and applies
updates; replaces Sources; removes Skills; and persists Favorite, Note, Personal
Tag, Draft, Update Candidate, history, integrity, and recovery state in the
Workspace SQLite control plane. Managed routes and commands use stable Managed
Skill identity rather than Slot Key.

Skill Markdown is read through the public Effective Revision file API and
rendered with `flutter_md`. Translation is wired through `skills_translation`
with user-configured providers, secure credential storage, content-addressed
cache, live block replacement, and explicit consent. App locale and Custom Agent
definitions are stored in SharedPreferences; Custom Agent changes reconfigure
the live catalog without replacing the Workspace repository.

## Self-update build inputs

The App uses the pinned `auto_updater` fork with native Sparkle/WinSparkle
dialogs. The only Dart build inputs are:

- `SKILLDECK_UPDATE_FEED_URL`: an HTTPS `appcast.xml` URL (or loopback HTTP for
  local smoke tests);
- `SKILLDECK_UPDATE_INTERVAL_MINUTES`: the native scheduler interval, defaulting
  to 360 minutes and requiring at least 60.

An ordinary local build supplies no feed URL and keeps self-update offline.
Release signing keys, R2 publication, and platform packaging remain release
steps; no private key is embedded in the App.

Development define files are provided in `debug.json` and `staging.json` at the
App root. Use them with:

```sh
flutter run -d macos --dart-define-from-file=debug.json
flutter build macos --release --dart-define-from-file=staging.json
```

## Verify

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter test -d macos integration_test/skills_manager_desktop_e2e_test.dart
flutter build macos --release
```

Use the corresponding `windows` device/build commands for SkillDeck App
validation. Linux commands remain applicable to `skills_workspace` package CI,
not to SkillDeck App release evidence. macOS x64 remains an explicit deferred
gate until restored.

For a Windows build that checks the production appcast, pass the feed explicitly;
an ordinary local build intentionally leaves self-update disabled:

```sh
flutter build windows --release --build-name=0.9.0 --build-number=2 \
  --dart-define=SKILLDECK_VERSION=0.9.0 \
  --dart-define=SKILLDECK_UPDATE_FEED_URL=https://assets.skilldeck.cc/skilldeck/stable/appcast.xml
```

The Windows installer is compiled separately from
`windows/packaging/inno/skilldeck.iss`. Its WinSparkle DSA signature must cover
the final installer bytes; publish the immutable installer before adding its
Windows enclosure to the shared appcast.
