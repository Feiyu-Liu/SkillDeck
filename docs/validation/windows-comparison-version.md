# Explicit Windows comparison identity: 2026-11-12

Issue: Feiyu-Liu/SkillsFlutter#60. These changes are local review candidates;
no plugin commit, App build, installer, or feed was published.

## Dependency handoff

Apply/publish the updater fork's platform/native commit
`dae29523565f0230c02708893c31579b18468eea` before its facade commit
`04fc94e9e023976f04ff2ae01ba26a9925ac2033`. The facade pins the former; the App
pins the latter. The existing macOS implementation remains at
`a04f0370c124c426640586aec9e410d26fcd881d`.

The release-tool change is my-skills commit
`03565e3114a4acbb0eba0dd78a2a0c7d5c7642c5`. Use that implementation and set
`build_version_define` to `SKILLDECK_BUILD_VERSION` in the local release config.
New Windows plan/prepare commands reject a missing/wrong key before invoking
the backend. Saved-run resume continues using frozen inputs and automation.

The unpublished plugin commits cannot currently be fetched from a clean remote
clone. Local validation used ignored path overrides pointing to the committed
plugin tree; its platform/native package bytes match the pinned first commit.
The tracked lockfile contains only the intended Git ref changes. Remove local
overrides and run frozen dependency resolution after those commits become
remotely available. Publishing and integration remain separate authorized work.

## Evidence

Flutter 3.47.5 / Dart 3.13.4 on macOS; Windows native tests ran on windows-env,
with Visual Studio 2026 / MSVC 19.51 and the cached Flutter Windows engine.
Original checkout changes and the Windows checkout's existing dirty test were
preserved. All fixtures and Windows builds used isolated directories.

- The combined App regression/updater/contract/widget selection ran 60 tests,
  all passed; whole-App strict analysis and formatting (339 files) passed.
  The App tests await the identity setter before interval/feed configuration
  through both the injected and facade paths. Missing/invalid identity and a
  rejected setter cannot initialize the scheduler. macOS keeps its prior path.
- Platform-interface tests: 6 passed; facade tests: 4 passed. Strict analysis
  passes for the interface package and facade lib/test. Full facade analysis
  still reports three existing Git-dependency publication warnings and the
  existing example `withOpacity` deprecation.
- Windows CTest: 2/2 passed. Argument types, empty/NUL/invalid UTF-8, UTF-16
  including a surrogate pair, repeated pre-init calls, post-init rejection,
  setter-before-init ordering, fallback, and the original dropped-callback
  assertion are covered. Native calls used by the production plugin are tested.
- The comparator is an unchanged extraction from WinSparkle v0.8.1 source
  commit `415acf557e8c15a12d8168d298b3b577fdbc6d54`, `src/updatechecker.cpp`;
  source SHA-256 and license are retained. Its verification script matched the
  exact upstream source, and the C++ ordering tests passed on macOS and Windows.
- Actual WinSparkle DLL probe: 14/14 passed. Two fixture executables contain
  ProductVersion/FileVersion `9.9.9+999`/`9.9.9.999` and
  `0.0.1+1`/`0.0.1.1`. Explicit `1.0.7+18` equals the feed regardless of those
  resources; `1.0.6+17` discovers it and `1.0.8+19` suppresses it. Both manual UI
  and initialization-driven scheduled checks ran. Legacy controls follow the
  differing resources. Each case starts a fresh process, uses a loopback feed
  and unique registry path, then cleans up that path. No payload is downloaded
  or installed.
- Release-tool tests: 49 passed, including direct metadata generation with
  signing mocked, both plus-form version fields, display versions, N-1/N merge,
  downgrade refusal, and the exact same-build immutable-enclosure error.
  Project wrapper tests: 11 passed. Windows PowerShell parsed the modified build
  script and exercised the quoted/unquoted Git-ref extraction.

Transient execution logs on the validation host: `/tmp/skilldeck60-native-tests.log`,
`/tmp/skilldeck60-dll-identity.log`, `/tmp/skilldeck60-fixture-resources.log`, `/tmp/skilldeck60-release-tools.log`,
`/tmp/skilldeck60-release-wrapper.log`, `/tmp/skilldeck-platform-app-tests.log`.
The reproducible native fixture sources and runners are committed in the fork.

## Remaining acceptance

The receipt identity comes from generated build inputs. It is not an extraction
of the compiled Dart constant from a final SkillDeck artifact. No final App
package was built to inspect that constant or its displayed version/build.
The release pipeline checks ProductVersion/FileVersion and records Git pins,
but those new gates were not exercised in an actual release run here.

Actual installed SkillDeck N-1 to N discovery/download/installation/relaunch,
then equality after restart under both manual and scheduled checks, remains
unperformed. The native fixture's fresh-process checks are narrower evidence.
Issue #60 therefore remains incomplete for release acceptance. Private config,
signing keys, production feeds, and installed user applications were not changed.

## Remote dependency follow-up, 2026-11-12

The updater platform/native and facade commits, and the release-tool commit,
are now available on their scoped remote feature branches. The App passed
frozen resolution from an initially empty Pub cache using its committed remote
Git URLs and exact lockfile revisions, without local path overrides or URL
rewrites. App strict analysis and 37 updater/identity tests passed afterward;
the latter reused the verified sqlite3 native asset after a release-asset
download failure. See the [combined follow-up](night-reviewed-2026-11-12.md#remote-dependency-follow-up-2026-11-12)
for commands, exact hashes, fresh package checks, and persistent worktree paths.

This follow-up completes remote dependency availability and resolution only.
The final packaged identity and installed Windows upgrade acceptance described
above remain open. No dependency branch was merged and no release was made.
