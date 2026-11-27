# T27–T32 Personal Sync implementation and validation

Date: 2026-11-27. Host: macOS arm64. Flutter 3.50.0, Dart 3.14.0.
Base: `1deff1f` on `claude/amazing-keller-unt4dd`; implementation commit:
`a0893de`. Three `gpt-6.1-sol` agents at high reasoning
implemented the work; the primary agent reviewed and ran the integrated gates.

## Delivered

| Task | Result |
|---|---|
| T27 | Pending-Lineage cleanup recovery, settled Attention Reasons, cursor recovery, identifier validation, account-condition reporting and quota retry |
| T28 | v0.2 metadata, tag vocabulary and Note Conflict contract draft; awaiting maintainer acceptance, with no M6 implementation |
| T29 | Real Workspace adapter through both App decorators; durable account/device sync state; exact Synced Origin round trips; real Worker pack test |
| T30 | macOS Settings Device Authorization sign-in, browser approval, secure session storage, offline account display and sign-out |
| T31 | Serialized sync runtime, automatic Feed Checks, local-change debounce, account notices, per-Skill status and Start/Stop Syncing |
| T32 | Content Attention Reason actions, incoming diff review, conflict side selection with separate publication, Device Exclusions and optional first-bootstrap activation |

Cloud stays off without a valid configured origin and on non-macOS builds.
The App injects `cupertino_http` 3.1.0. Version 3.1.1 could not resolve against
the existing Workspace Native Assets dependencies. Sessions use the existing
`flutter_secure_storage` 11.0.0 configuration. Network reconnect uses
`connectivity_plus` 7.3.2; system wake uses a macOS notification channel.

## Maintainer-approved additions

- Secure storage also retains the last verified account ID, email and session
  expiry. Offline display does not authorize a runtime. The UI displays email,
  since the current account response has no display name.
- Local Git paths are Device-Bound local sources. Source paths stay on their
  originating Device. Cloud labels use the common Workspace validation domain.
- Device-Bound sources carry an optional opaque `originSourceId`. New local
  IDs are HMAC-derived with a random installation-local seed; display labels
  remain human-readable, and recipients preserve the ID verbatim.
- Workspace revision reads expose a local opaque Source Epoch. Sync stores the
  acknowledged epoch, so explicit Source Replacement is recognized even when
  its address and content are unchanged. Committed install/replacement results
  return their epoch. Content apply, replacement and removal can reject an old
  expected epoch before mutation. The epoch is not sent to the Cloud API.
- The existing App lacked Draft publication/discard and conflict-review UI.
  The approved `t32-review-seams-contract.md` adds generic Workspace operations
  for a read-only pack diff and reviewed conflict-side selection. Selection
  updates the Draft; publication remains a separate user action. Existing
  journaling and recovery are reused, with no database migration.

The corresponding local apply contract is recorded in
`../m5-sync-apply-contract.md`. These changes do not implement Sharing, Teams,
Marketplace, or the proposed v0.2 metadata endpoints.

## Final gates

Commands ran from their owning package or App directory.

| Scope | Gate | Exit | Result |
|---|---|---:|---|
| Workspace | `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` | 0 | Locked dependencies |
| Workspace | `dart format --output=none --set-exit-if-changed .` | 0 | Clean |
| Workspace | `dart analyze --fatal-infos` | 0 | No issues |
| Workspace | Full `dart test -j 1 --coverage=… --reporter expanded`, in file batches | 0 for every batch | 1,689 passed; one existing opt-in network test skipped |
| Workspace | `dart test -j 1 integration_test` | 0 | 2 passed |
| Workspace | Coverage formatting, repository filter and `check_coverage.dart … 85` | 0 at each step | **89.22%**, 21,485/24,082 lines; gate 85% |
| Cloud | `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` | 0 | Locked dependencies |
| Cloud | Format and `dart analyze --fatal-infos` | 0 each | Clean |
| Cloud | `dart test --coverage=coverage/t27-t32-final --reporter expanded` | 0 | 92 passed |
| Cloud | LCOV formatting | 0 | Production excluding test fakes **92.84%**, 1,115/1,201 lines; Reconciler **88.14%**, 431/489 lines |
| App | `flutter pub get --enforce-lockfile` | 0 | Existing configured registry and local overrides retained |
| App | `dart format --output=none --set-exit-if-changed .` | 0 | Clean; existing probe-directory package-resolution warning remains |
| App | `flutter analyze --fatal-infos --no-pub lib test integration_test` | 0 | Production and test code clean |
| App | `flutter analyze --fatal-infos --no-pub` | 1 | Five existing infos in unrelated untracked Windows probes; see below |
| App | `flutter test --no-pub --reporter expanded` | 0 | 1,302 passed; opt-in Worker test skipped in the ordinary suite |
| App | `flutter test --no-pub -d macos integration_test/skills_manager_desktop_e2e_test.dart` | 0 | 6 passed; Debug desktop build succeeded |
| App / Worker | Explicit M4-7 real pack round trip | 0 | 1 passed against local workerd, isolated D1 and R2 |
| App debug | Isolated Cloud Settings fixture, hot reload and hot restart | Success | Reloaded 4 libraries in 764 ms; restarted in 806 ms; fixture process then closed |
| Repository | `git diff --check` | 0 | Clean |

The initial monolithic Workspace run exhausted disk space after 1,426 passes.
Its exited compiler temporary directory was removed. The final run covered all
192 test files in batches of at most 35. Pass counts were 229, 324, 420, 226,
356 and 134. The first batch was rerun after the final epoch guards, replacing
its earlier coverage data. All six final coverage inputs therefore describe
the final production code. Coverage used the repository's existing generated
code filter.

Full-directory App analysis reports one `curly_braces_in_flow_control_structures`
and four `avoid_print` infos in `tool/windows_http_probe/{bounds,cert_cases,pack}.dart`.
Those files were untracked before this task and were preserved. This is not a
claim that the whole local directory passes strict analysis. App dependency
and UI evidence also uses the pre-existing machine-local `next_ui` override;
it is not a clean CI/release dependency qualification.

During commit preparation, only the new Cloud dependencies and the direct
`http` classification were included in the App lockfile. Existing unrelated
local upgrades, the registry override, the local `next_ui` path override and
the unrelated CocoaPods checksum change remain uncommitted. The committed
lockfile retains the prior Git pin for `next_ui` and `pub.dev` registry URLs.
An isolated App manifest and lockfile, without local overrides, passed
`PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` (exit 0).
This additional check establishes locked dependency resolution, not another
full test run with those dependency versions.

## Evidence and boundaries

- Native tests cover both conflict-side choices; rename, deletion, binary and
  executable content; already-resolved edits; stale/foreign review tokens;
  cancellation and cleanup; and process interruption before and after commit.
- The identical-head Source Replacement regression checks that old-epoch
  content apply and removal return `staleSnapshot` with no change to the Skill,
  repository revision, Journal or Operation Records.
- Two real temporary Workspaces verify content publication, Draft blocking,
  explicit conflict publication, source replacement between same-named
  directories, and same-address replacements with both changed and identical
  bytes. The receiver stores its committed epoch and does not echo a new
  Generation back to the service.
- App tests cover all content reasons and their actions, cancellation of
  destructive confirmation, stale confirmation rejection, linked occupied-slot
  identity, selected activation versus dismissal, and explicit 401 responses
  even when a subsequent session read would succeed or be offline.
- M4-7 uses the actual Dart `CloudApi` and real exported/imported packs over a
  loopback HTTP bridge to the actual Worker handler in workerd. Its login uses
  synthetic Device Authorization accounts and captured test email delivery.
  This proves client/Worker pack interoperability, not staging transport or
  two physical Macs. The fake service's real-pack mode deliberately does not
  replace the Worker's pack verification or ancestry checks.
- The desktop E2E runner could not foreground its window through `open`, but
  the separately launched test process completed all six tests. Native build
  warnings about the existing updater's Swift Package Manager support remain.
- A temporary Cloud Settings debug fixture used an in-memory session store and
  a mock HTTP client. Hot reload and hot restart succeeded. The first fixture
  omitted its explicit English locale and reported a localization warning;
  the fixture was corrected before the successful restart. This fixture did
  not replace or authenticate the installed App.

## Remaining acceptance and compatibility notes

- v0.2 is a design draft. Its open questions require maintainer acceptance
  before T33/T34 implementation.
- Manual staging sign-in with the new App, physical network reconnect/wake,
  and real dual-Mac App acceptance belong to subsequent acceptance work. They
  were not claimed by these local tests. No deployment or release occurred.
- Pre-epoch experimental state can baseline its current epoch, but cannot
  reconstruct an identical-source reset that happened before that baseline.
  An originating pre-ID Device-Bound source can advance one Generation when
  it first gains its opaque provenance ID. Legacy received values remain
  readable and retain the omitted ID.
- If the App quits abruptly before displaying the first activation offer,
  the in-memory list for that offer can be lost. Installed Skills remain
  inactive and can be activated from their detail pages. The shown marker is
  durable; no onboarding operation ledger was introduced.
- Existing unrelated worktree changes were preserved. The maintainer later
  authorized local commits; the implementation is `a0893de`. Nothing was
  pushed, merged, or deployed. `branch-doc/` must stay out of `main`.
