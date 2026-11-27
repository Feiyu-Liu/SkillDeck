# M6 metadata synchronization: implementation and acceptance

Completed 2026-11-28, following the maintainer-approved plan of 2026-11-27.
Public checkout base: `1e993ab`. At validation time, the M6 changes in both repositories were
uncommitted. Three `gpt-6.1-sol` agents at high reasoning implemented the
service, client and Workspace/App changes; the primary agent reviewed and
ran the integrated gates.

## Delivered behavior

- Favorites, Notes, tag assignments and the account vocabulary synchronize
  separately from content. Existing content status, Note attention and
  transient metadata waiting can be shown together.
- Notes use current/incoming comparisons. Equal text settles; differing
  concurrent text stays available for explicit selection or combination. A
  third local text is retained. Resolution saves the chosen text locally
  before the cloud CAS; failed requests and newer local edits do not erase it.
- First association uses cloud-edited Favorite/Assignments, including empty
  assignment sets. Untouched cloud fields accept local values. Existing
  differing nonempty Notes remain reviewable. New installs take cloud values.
- Vocabulary remains global, including its effect on Device Only Skills.
  Old tags are imported through retained assignments on synced Skills. New
  tags belong to the connected account. A returning account keeps its own
  eligible pending tags but does not automatically import another account's
  new tags.
- A stable installation-derived creation key follows a tag through lost
  responses, rename, merge and deletion. Deleted aliases do not recreate the
  logical tag. There is no operation outbox or indefinite Note-history ledger.
- Field limits remain 4 KiB UTF-8 Notes, 64-scalar tag names and 256 live tags.
  Correction actions reuse the existing Note and tag editors. Known quota
  failure stops further doomed creates in that pass and retries after recovery.
- An old service returning 404 for vocabulary keeps content sync available.
  Authentication and transport failures retain their distinct handling.

## Local consistency and recovery

`RemoteSkillMetadata` and vocabulary requests accept a local
`expectedRepositoryRevision`. Cloud supplies it on every apply. A stale read
is rejected before mutation/no-op handling, and the existing commit guard
protects the later transaction window. The real Command Host write path is
included in the interleaving regression.

A missed sequence of cloud renames can exchange two names without merging
their identities. `RemoteTagVocabulary.renameMany` applies that final name
set in one existing SQLite transaction, preserving IDs, colors and assignments.
Reserved unique keys exist only inside the transaction. A late SQL abort and
reopen leave names, assignments and the committed-change feed intact.

Normalization stays in the allowed application layer; a public API extension
exposes `PersonalTag.normalizedName`. The existing canonical helper is shared.
Actual Dart normalization vectors also exercise the Worker implementation;
notably Dart simple uppercase is not JavaScript full uppercase for `ß`.

After a future-cursor/server rollback, differing lower-version cloud Notes
cannot overwrite the last agreed local text. Equal values settle. Confirmed
lower tag versions stop causing perpetual retries, and subsequent Feed versions
are processed normally. Local state write failure preserves the old checkpoint,
reports only `local_state_io`, and stops automatic work.

## Service and transport

Migration 0005 applies to the two account data shards. It adds metadata, tag
and alias tables and typed `(account,kind,id)` Feed keys while retaining old
sequence numbers and cursor meanings. Field changes, derived assignments,
versions and Feed entries commit together. Cursor state and page reads also
share one D1 batch snapshot to prevent a retention-sweep race.

Metadata request bodies are bounded to 32 KiB. Projected library pages are
limited to 2 MiB after JSON encoding, with bounded D1 result materialization
and a continuation after the last returned row. The client's 4 MiB JSON bound
is unchanged. The existing monotonic scheduler honors Retry-After across
metadata writes, recovery reads, automatic debounce and Feed Checks.

The public and private copies of the accepted v0.2 contract were compared
byte-for-byte. No dependency declaration or service configuration was changed.

## Final verification

Host: macOS arm64; Flutter 3.50.0, Dart 3.14.0, supported Node 26.12.0 for the
service. Commands ran in their owning project.

| Scope | Check | Exit | Result |
|---|---|---:|---|
| Service | `npm test` | 0 | 460 passed |
| Service | `npm run test:personal-sync` | 0 | 18 passed in actual workerd |
| Service | Typecheck, format and Worker build | 0 each | Passed |
| Service | Local cf migrations on two disposable D1 shards | 0 | Five migrations applied on each |
| Workspace | Locked pub get, format and strict analysis | 0 each | Passed |
| Workspace | Entire test directory, `dart test -j 1 --coverage=…`, in batches | 0 for all batches | 1,692 passed; one existing opt-in network test skipped |
| Workspace | `dart test -j 1 integration_test` | 0 | 2 passed |
| Workspace | Coverage formatting, repository filter, 85% gate | 0 each | **89.24%**, 21,538/24,136 lines |
| Cloud | Format, strict analysis and full Dart suite | 0 each | 125 passed, including 33 metadata regressions |
| Cloud | Production line coverage, excluding test helpers | — | **91.85%**, 2,570/2,798 lines |
| App | `flutter pub get --enforce-lockfile` | 0 | Existing local resolution retained |
| App | Format | 0 | Clean; existing untracked-probe resolution warning remains |
| App | `flutter analyze --fatal-infos --no-pub lib test integration_test` | 0 | Production/test code clean |
| App | Full-directory `flutter analyze --fatal-infos --no-pub` | 1 | Five pre-existing infos in untracked Windows probes |
| App | `flutter test --no-pub --reporter expanded` | 0 | 1,310 passed; two opt-in Worker tests skipped here |
| App | `flutter test --no-pub -d macos integration_test/skills_manager_desktop_e2e_test.dart` | 0 | 6 passed; debug desktop build succeeded |
| App + Worker | Explicit M4/M6 bridge run | 0 | Both opt-in tests passed |
| App debug | Isolated in-memory Cloud Settings fixture | Success | Hot reload: 3 libraries in 1,744 ms; hot restart: 2,820 ms; fixture then closed |
| Both repositories | `git diff --check` | 0 | Clean |

The final Workspace run covered all 192 test files in six batches to bound
compiler disk usage. Batch pass counts were 232, 324, 420, 226, 356 and 134.
Fresh coverage was collected after fixing the dependency-direction issue;
no pre-fix coverage inputs were used. The first App full run found a Chinese
terminology violation, fixed before the final full run.

The M6 bridge used two independent Device Authorization sessions for the same
synthetic account and two real temporary Workspaces against local workerd,
D1 and R2. It proved initialization, field transfer, global tag changes on
Device Only Skills, restart, missed name swaps, Note conflict/third text, and
resolution failures with local interleaving. The test now requires an empty
dedicated test account before any remote writes. Test tokens stayed in process
environment and were redacted from captured output.

## Boundaries and next acceptance

- These are local functional and recovery results. Manual staging sign-in
  with the new App and real dual-Mac App acceptance remain M8 work. No live
  migration, deployment or release occurred during validation.
- Deploy the service migration and metadata-aware Worker before enabling new
  App metadata traffic. After typed metadata Feed rows exist, a Worker rollback
  must still understand those rows; the private README records this constraint.
- The App checks use pre-existing local dependency upgrades and the machine-local
  `next_ui` override. They are not a clean CI/release dependency qualification.
- The five full-directory analyzer infos are in the pre-existing untracked
  `tool/windows_http_probe/{bounds,cert_cases,pack}.dart`; they were preserved.
- `open` could not foreground the E2E window, but its separate test process
  completed all six tests. Existing updater Swift Package Manager warnings
  remain outside this task.
- Hot reload/restart used a temporary debug fixture with a mock HTTP client
  and in-memory session store; it did not open a user Workspace or replace
  the installed App session.
- Notes may need another review after extreme delayed or lost responses. This
  is the approved tradeoff for preserving current texts without indefinite
  private Note history. Beta account quotas/deletion and later Cloud phases
  are unchanged milestones.
- Unrelated dirty files and previous validation artifacts were preserved.
  `branch-doc/` must not be merged into `main`.
