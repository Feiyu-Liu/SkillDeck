# ExecPlan: T27 M4 review fixes in the Reconciler

Fixes M4-1 to M4-5 from `../reviews/2026-11-27-m4-review.md`. Client side only.
Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

The Reconciler recovers from a pending Lineage that the service cleaned up. A
Skill that needs the person's attention no longer slows or repeats sync for
the other Skills.

### Context

- **Read first:**
  - the review, items M4-1 to M4-5;
  - contract v0.1: "Create a Lineage" (the 24-hour rule and `clientKey`) and
    "Account Change Feed";
  - `lib/src/sync/reconciler.dart` and T04's `FeedCheckScheduler`.
- **A link with a `clientKey`** has never been advanced from this Device;
  `_remember` drops the key after the first head. This card relies on that.

### Contract

- **M4-1, pending Lineage gone:**
  - For a link that still holds its `clientKey`, a 404 from read, upload, or
    Head Advance clears the `lineageId`. Then create again with the same key,
    upload, and advance, all in the same check.
  - For a link without a `clientKey`, a 404 from upload or Head Advance reads
    the Lineage again. A 404 from that read keeps today's outcome, "Missing
    from the Cloud Library after a reset".
  - No documented 404 throws.
- **M4-2, Needs Attention:**
  - Only Waiting to Upload holds the feed cursor or the Workspace cursor, and
    only it makes the check a failure.
  - Needs Attention and account conditions are settled for the cursor.
  - A Skill with an Attention Reason is reconciled again on:
    - a resolving action;
    - a local committed change to it;
    - a newer feed entry for its Lineage.
  - **First check the Workspace committed-change feed:** does it record
    publishing a Draft, discarding a Draft, and resolving a Sync Merge
    conflict? Record the answer in the Decision Log.
    - If any of them is missing, also reconcile the Skills that hold an
      Attention Reason on each Feed Check, without holding the cursor.
    - Skip the download when neither the Lineage `version` nor the local
      Effective has changed since the last attempt. Keep that pair in
      `SyncStateStore`, not in an outbox.
- **M4-3:** a feed entry for an unlinked Lineage that answers 404 is skipped,
  with no outcome.
- **M4-4:** a library page answering 410 `cursorExpired` restarts the listing
  from the first page, once per bootstrap. A second 410 ends the bootstrap as
  not completed.
- **M4-5:** `CloudApi` accepts a Lineage ID only if it matches
  `^[A-Za-z0-9_-]{1,64}$`. Any other ID throws `ArgumentError` before a request
  is made.

### Acceptance

Each item is a test with the fakes.

- **M4-1:**
  - create succeeds, the upload fails, and the fake's clock passes 24 hours.
    The next check creates the Lineage again with the same `clientKey`, and
    ends Synced, with one Lineage in the library;
  - the same case, with the Lineage cleaned between read and upload, also ends
    Synced;
  - a linked Skill whose Lineage disappears after its first head gets "Missing
    from the Cloud Library after a reset", and the check still completes the
    other Skills.
- **M4-2:**
  - with a conflicting Skill A and a clean incoming change to Skill B, the
    first check gives A Needs Attention and B Synced, and returns success;
  - the cursor moves past both entries;
  - a second check with no new entries makes no pack download;
  - resolving A, by the path the Decision Log names, reconciles it and ends
    Synced;
  - the scheduler's next delay after that check is the normal interval, not a
    backoff.
- **M4-3, M4-4, M4-5:** one test each.
- **Existing tests** still pass. Change one only where its expectation was the
  behaviour this card replaces, and say which in the Decision Log.
- **Gates:** T16's gates from `packages/skills_cloud/`, each with its own exit
  code, and line coverage of `reconciler.dart` reported.

### Scope fence

- **In scope:** `packages/skills_cloud/`.
- **Out of scope:**
  - M4-6 and M4-7 (the M7 adapter);
  - the service;
  - `skills_workspace`.
- **Expected size:** about 3–6 files, 300–600 lines including tests.

### Stop and ask if

- The committed-change feed records none of the three resolutions, and the
  per-check fallback needs Workspace reads the port does not have.
- A fix needs a new public type in `skills_cloud.dart` beyond a field on
  `SyncLink`.

## Maintained by Codex

### Progress

- [x] Confirm when Workspace emits a committed-change entry for Draft and conflict actions.
- [x] Recover pending Lineages, settle Attention Reasons and account conditions, and handle feed and library edge cases.
- [x] Verify all five review items with the fakes and run the package gates.

### Decision Log

- Publishing a Draft and publishing a Sync Merge conflict resolution change the Effective revision and appear in the feed. `DriftCommittedChangeFeed.recordSelection` stamps the selection changes. Discarding a Draft or abandoning a conflict without publishing only deletes Draft or candidate state, which `recordMutation` ignores.
- `SyncLink.attentionAttempt` records the last blocked Lineage version, the local Effective, and the typed reason in `SyncStateStore`. The existing link version and Effective still mean the last synced head. A Feed Check can inspect a blocked Skill again without fetching its pack for an unchanged pair.
- Successful Draft discard and conflict abandonment must call `reconcileSkill` explicitly. That path retries the same pair. Successful conflict publish triggers `checkLocalChanges` through the committed-change feed. The existing Draft regression now uses explicit reconciliation after discard.
- `Reconciler.accountCondition` reports the existing typed account condition from a check even when no Skill is linked, so the App can handle sign-in expiry after a feed or library response.
- An account quota rejection records `SyncLink.uploadBlockedByQuota`. It settles the Workspace cursor and retries on a later scheduled check, including after restart. Success clears the observation.

### Surprises

- With the shell's default package mirror, `dart pub get --enforce-lockfile` exited 65. All locked dependencies use `pub.dev`, and the same gate with that registry exited 0.

### Follow-ups

- T29 persists `SyncLink.attentionAttempt`. T32 routes resolving actions that leave the Effective unchanged through `reconcileSkill`.

### Outcome

The fake tests cover cleanup before read, upload and Head Advance, 404s after a first head, conflict isolation and a normal scheduler interval, unlinked 404s, a single library retry, and Lineage IDs on all request paths.

On macOS arm64 with Dart 3.14.0, all gates ran from `packages/skills_cloud/`.

| Command | Exit | Result |
|---|---:|---|
| `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` | 0 | Lockfile unchanged |
| `dart format --output=none --set-exit-if-changed .` | 0 | Clean |
| `dart analyze --fatal-infos` | 0 | No issues |
| `dart test --reporter expanded` | 0 | 92 passed in the integrated worktree |
| `dart test --coverage=coverage --reporter expanded` | 0 | 92 passed |
| `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --package=. --report-on=lib` | 0 | `reconciler.dart` 431/489 lines (88.14%) |
