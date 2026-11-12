# Combined local validation, 2026-11-12

Candidate branch: `feat/night-reviewed`, based on `148245bd`. Production and
fixture changes through `d112445` were tested together. Original `main` remains
at `148245bd`; its existing `.gitignore` and App lockfile changes were preserved.

| Change | Combined commit | Original commit |
| --- | --- | --- |
| Persisted first-added sorting | `a24b8f7` | `fea1102` |
| Settings lazy-flush selection race (#36) | `b1c0dee` | `6bfb682` |
| Explicit Windows updater identity (#60) | `ed4bd5a` | `81fdbea` |
| Startup observability and deterministic counters | `6a4e5e2` | `1e3077d` |
| Safe provenance links and browser fixture | `63144f4` | `21caf4f` |
| Native startup fixture and measured evidence | `d112445` | `ad66c60` |

Environment: physical macOS arm64, Flutter 3.47.5 / Dart 3.13.4.
`PUB_HOSTED_URL=https://pub.dev` was fixed for the complete validation command
chains. Workspace dependencies used the committed frozen lock. The App used
ignored local overrides for the exact committed updater package trees; its
tracked Git pins were restored after resolution. All other locked dependencies
remained unchanged. CocoaPods Manifest.lock matched the committed Podfile.lock.

The fork requires platform/native commit
`dae29523565f0230c02708893c31579b18468eea`, then facade commit
`04fc94e9e023976f04ff2ae01ba26a9925ac2033`. Release tooling requires my-skills
commit `03565e3114a4acbb0eba0dd78a2a0c7d5c7642c5`. These commits are local and
have not been pushed or published.

## Combined checks

| Check | Result |
| --- | --- |
| Workspace `dart test -j 1 --coverage=coverage` | 1,582 passed; one existing network-tagged test skipped |
| Official LCOV formatter, generated-code filter, 85% gate | **88.78%**, 19,808 / 22,312 lines; 216 records retained, two generated records excluded |
| Workspace `dart test -j 1 integration_test` | One native Revision worker test passed |
| Workspace `dart run tool/run_native_abi_test.dart` | Native runtime lifecycle and ABI harnesses passed |
| Workspace strict analysis / format | Clean; 468 Dart files unchanged |
| App `flutter test --no-pub --concurrency=4` | **1,207 passed** |
| App strict analysis / format | Clean; 348 Dart files unchanged |
| Project release wrapper tests | 11 passed |
| Release-tool offline suite | 49 passed |
| Windows native plugin CTest / actual WinSparkle DLL probe | 2/2 and 14/14 passed; details in [Windows evidence](windows-comparison-version.md) |

macOS native source acceptance also passed: the production source-link widget
was tapped, the actual native launcher opened the default browser, and the
fixture received the matching loopback GET. This was an automated native test;
manual visual usability and other desktop platforms remain unverified.

The combined startup fixture passed with 85 Skills / 340 copy Activations.
All 4,250 files / 49,314,100 bytes retained their content and metadata hashes.
Its first mount was 2,170.637 ms and warm median 1,018.895 ms; this compatibility
run is separate from the same-condition [startup comparison](../../packages/skills_workspace/tool/benchmarks/startup_2026_11_12.md).
The measured patch adds observability; the A/B evidence does not establish a
general startup speedup. An owned combined fixture then hot reloaded successfully
(3 / 3,395 libraries, 1,723 ms), exited normally, and its temporary entrypoint
was removed. The native tool emitted a foreground warning, but both fixture
tests and the actual browser GET completed successfully.

## Evidence and remaining gates

Raw combined logs are `/tmp/skilldeck-night-reviewed-{workspace-full-coverage,coverage-gate,workspace-native-integration,workspace-native-abi,workspace-analysis,workspace-format,app-full,app-analysis,app-format,source-browser-native,startup-native,hot-reload}.log`.
Coverage is at `packages/skills_workspace/coverage/lcov.info` in this worktree.
The Settings baseline failure is retained at `/tmp/skilldeck-36-red.log`, with
`_SettingsScreenState.build` and `_reconcileWorkspaceSelection` in its stack.
Sorting was reproduced during implementation; its original raw red output was
not retained. The combined suites include its DB/adapter/comparator regressions.
Startup A/B raw evidence is under `/tmp/skilldeck-startup-evidence`.

#60 still needs remote availability of the pinned fork commits, clean remote
frozen resolution, inspection of the compiled identity in a final App artifact,
and an actual installed Windows N-1 download/install/relaunch/equality cycle.
Receipt identity checks validate build inputs, not extracted artifact bytes.
Full fork-facade analysis retains three pre-existing Git-dependency publication
warnings and the existing example deprecation; interface and facade lib/test
analysis passed. Package filesystem/runtime acceptance here is macOS evidence.
No real user Workspace, signing keys, private release config, production feed,
or installed production App was changed. No issue was closed.

## Remote dependency follow-up, 2026-11-12

The candidate was restored at `5d70228d504d3e1b60fd4021a93ecab8cb592f03`
in a persistent isolated worktree. The previous `/tmp` worktrees and raw logs
listed above were not recovered; the combined-suite results above remain the
historical record from that run.

The updater branch `feat/explicit-comparison-version` is now available on
`https://github.com/Feiyu-Liu/auto_updater.git` at
`04fc94e9e023976f04ff2ae01ba26a9925ac2033`, including platform/native ancestor
`dae29523565f0230c02708893c31579b18468eea`. The release-tool branch
`fix/winsparkle-release-identity` is available on
`https://github.com/Feiyu-Liu/my-skills.git` at
`03565e3114a4acbb0eba0dd78a2a0c7d5c7642c5`. Neither branch was merged.

The App passed `flutter pub get --enforce-lockfile` with Flutter 3.47.5 /
Dart 3.13.4, `PUB_HOSTED_URL=https://pub.dev`, and a newly created, initially
empty `PUB_CACHE`. System/global Git configuration was disabled for this
resolution. There were no `pubspec_overrides.yaml` files or Git URL rewrites.
The resolved updater package roots point into the new Git cache at the exact
facade/platform/macOS revisions recorded in the committed lockfile. The
tracked lockfile remained byte-for-byte unchanged.

Fresh follow-up checks:

| Check | Result |
| --- | --- |
| App `dart analyze --fatal-infos` after remote resolution | Clean |
| App updater/identity contracts: `flutter test --no-pub --concurrency=4 test/contracts/product_identity_and_updater_contract_test.dart test/features/self_update` | 37 passed |
| Updater platform interface `flutter test --no-pub` / strict analysis | 6 passed / clean |
| Updater facade `flutter test --no-pub` / `dart analyze --fatal-infos lib test` | 4 passed / clean |
| Project `python3 -m unittest discover -s tool/tests` | 11 passed |
| Release tool `python3 -m unittest test_desktop_release` | 49 passed |

The first App test invocation and its unrestricted retry failed while fetching
the sqlite3 3.5.2 arm64 macOS native asset: the GitHub release-asset connection
was refused. The passing test run reused only that package's existing native
asset after verifying SHA-256
`6d80ba56cff1fa44f62bebc3e6b6b71513cc628862a9745c223c7bea8bf813f3`.
This does not change the clean remote Git dependency-resolution result; it is
not evidence that every native artifact can be freshly downloaded.

The restored worktrees are under
`/Users/tilapia/TilapiaFiles/Projects/Worktrees/` with names
`skilldeck-night-reviewed-20261112`,
`auto-updater-comparison-version-20261112`, and
`my-skills-winsparkle-release-identity-20261112`. Fresh raw logs are alongside
them as `skilldeck-night-*.log` and `auto-updater-*.log`; the isolated Pub cache
is `.validation-cache/skilldeck-night-20261112`.

Remote availability and frozen resolution are now verified. Final packaged
App identity inspection and the installed Windows N-1 download/install/relaunch
and post-restart equality cycle remain unperformed. No release, feed change,
installed App, user Workspace, or private release input was involved.
