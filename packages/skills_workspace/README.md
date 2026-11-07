# skills_workspace

`skills_workspace` is the standalone transactional backend for the local Skill
Workspace bounded context. It owns SQLite control-plane state, App-managed
revision history, durable filesystem publication, source acquisition,
activation, recovery, and user Library metadata behind one `SkillsRepository`
facade.

The package supersedes the former Core and Library package split. Skills Manager
composes this facade directly as its sole Skill Workspace authority.

## Runtime shape

- Dart API and application/domain logic remain Flutter-free.
- Drift and SQLite own control-plane metadata and the operation Journal.
- A project-owned Native Assets hook statically links pinned libgit2 1.9.7 into
  a private local-only revision engine.
- Public HTTPS Git Sources fetch through the networked embedded libgit2
  (ADR-0106); system Git serves SSH and local locators and is the fallback.
  Internal revision history never uses system Git.
- Flutter is used only by `example/` as a real desktop package-loading harness.

The public entry point is `lib/skills_workspace.dart`. Drift rows, SQLite
connections, Git handles, recovery paths, and generated FFI bindings are not
public API.

## Locked toolchain

Development and release evidence use Dart 3.13.4 and Flutter 3.47.5. Resolve
the package and example with their committed lockfiles:

```bash
dart pub get --enforce-lockfile
cd example
flutter pub get --enforce-lockfile
```

Even though this is a package, its lockfile is release input because generated
Drift, ffigen, Native Assets, SQLite, and native-link output are version
sensitive.

The Flutter desktop host supports macOS 13.0 and later. Flutter 3.41.9 supplies
macOS 13 as the Code Assets target, and the selected `sqlite3` 3.5.2 Native
Asset is built for that same minimum. The independently built revision shim
retains its lower x64 10.15 and arm64 11.0 deployment targets, but those lower
targets do not redefine the minimum of the complete application bundle.

## Generated code

The selected Drift schema workflow is:

```bash
dart run build_runner build
dart run drift_dev schema dump \
  lib/src/infrastructure/database/workspace_database.dart \
  drift_schemas/drift_schema_v3.json
dart run drift_dev schema generate \
  drift_schemas test/infrastructure/database/generated
dart run ffigen --config ffigen.yaml
git diff --exit-code
```

`dart run tool/regenerate.dart` runs the four generation commands. Generated
files are committed and must not be edited by hand.

## Local verification

Run package checks serially so native compilation and test workers do not
compete for memory:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test -j 1
dart test -j 1 integration_test
dart test -j 1 --coverage=coverage
dart run coverage:format_coverage \
  --lcov --in=coverage --out=coverage/lcov.raw.info --package=. --report-on=lib
dart run tool/filter_coverage.dart coverage/lcov.raw.info coverage/lcov.info
dart run tool/check_coverage.dart coverage/lcov.info 85
dart run tool/run_native_abi_test.dart
```

The Flutter host checks run from `example/`:

```bash
flutter analyze --fatal-infos --no-pub
flutter test --no-pub
flutter test --no-pub -d macos \
  integration_test/native_revision_engine_test.dart
```

Use `windows` or `linux` as the device on those hosts; Linux requires a display
server such as `xvfb-run` in headless CI.

## Release evidence

Build release evidence from a clean Flutter graph. Flutter 3.41.9 installs
Native Assets from Debug and Release into the same `build/native_assets`
directory, so a Debug desktop integration run can otherwise leave a thin
host-architecture framework behind a valid cached Release install stamp:

```bash
cd example
flutter clean
flutter pub get --enforce-lockfile
flutter build macos --release --no-pub
cd ..
```

Use `windows` or `linux` in the final command on those hosts. Run these commands
serially and inspect the resulting release bundle rather than an intermediate
hook output.

`tool/inspect_native_artifact.dart` verifies the final bundled Native Asset,
not an intermediate object. It checks architecture, the exact exported shim
allowlist, dynamic dependencies, SHA-256, byte size, and the macOS deployment
target. The release workflow strips the bundled Skills Workspace and SQLite
assets before signing and measurement. `tool/verify_stripped_native_artifact.dart`
then rejects Mach-O local/debug symbols, ELF debug/static-symbol sections,
PE/COFF symbol tables, and native debug sidecars. It emits machine-readable
evidence for both package-owned assets. `tool/measure_release_size.dart`
compares the Flutter release bundle with a package-loading baseline and
attributes the stripped embedded libgit2 and SQLite payloads.

The final bundle is tested after stripping and signing, not only through an
intermediate Debug host. `tool/run_release_bundle_smoke.dart` launches the
packaged desktop executable in a non-UI smoke mode and requires it to load the
bundled engine, create a Store, and report the pinned libgit2 version. macOS CI
also performs `codesign --verify --deep --strict` on that same bundle before
the smoke run. Windows and Linux prove final bundled loading through the direct
C ABI gate against the Release DLL/SO because their GUI executable is not a
portable command-line output surface.

The CI workflow has three explicit tiers: pull requests use the Linux quick
gate, `main` uses the active macOS arm64, Windows x64, and Linux x64 merge gates,
and version tags or a manually selected `release` tier add Release packaging,
native-artifact inspection, ASAN/UBSAN, size measurement, and evidence uploads.
macOS x64 remains a deferred release gate until its runner is restored. SSH
development hosts (`windows-env` and `linux-env`) provide additional
real-platform evidence for the exact commit but do not replace clean CI runners.

## Native sources and licenses

The libgit2 source pin, digest, switches, and update procedure live in
`native/libgit2.lock.json`. See `native/THIRD_PARTY_NOTICES.md` and
`native/third_party/libgit2/COPYING` for licensing.
