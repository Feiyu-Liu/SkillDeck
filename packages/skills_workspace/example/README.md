# Skills Workspace desktop harness

This Flutter app is the package-loading and desktop integration harness for
`skills_workspace`. It loads the package-owned Native Asset, verifies the
pinned libgit2 version, creates a bare Revision Store, and exposes a visible
success/failure state.

Run host tests:

```bash
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos --no-pub
flutter test --no-pub
```

Run the real desktop integration harness:

```bash
flutter test --no-pub -d macos \
  integration_test/native_revision_engine_test.dart
```

Replace `macos` with `windows` or `linux` on that host. The integration suite
covers package loading, commits, clean and conflicted merges, executable mode,
pack creation, and pack restoration without system Git.
