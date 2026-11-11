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
