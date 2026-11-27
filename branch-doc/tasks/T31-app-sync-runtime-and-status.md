# ExecPlan: T31 App: the sync runtime and per-Skill Sync Status

Milestone M7, part 3. After T27, T29, and T30. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

A signed-in App keeps chosen Skills in sync with no user action, and shows each
Skill's Sync Status. Content only; metadata waits for M6.

### Context

- **Read first:**
  - `../phase1-plan.md`: Change delivery (R8) and Sync Status (R10);
  - `packages/skills_cloud/CONTEXT.md`, Sync Status and the Attention Reason
    table;
  - `FeedCheckScheduler` and `Reconciler` in `packages/skills_cloud`;
  - T29's adapter and state store, T30's providers.
- **R8:** Feed Checks run on launch, on foreground, on reconnect, on wake, and
  every 2 minutes. Pack storage is never polled.

### Contract

- **`CloudSyncRuntime`,** one per signed-in account, owned like
  `SkillsManagerRuntime`, for the process lifetime of that account:
  - built when T30's provider reports signed in; disposed on sign-out or an
    account change. A new account gets a new `FileSyncStateStore`;
  - **serialization:** Feed Checks, local-change checks, and user actions run
    one at a time through one queue. No two Reconciler calls overlap;
  - **triggers:**
    - Feed Check: launch, App foreground, network reconnect, system wake, and
      `FeedCheckScheduler`'s timer;
    - local-change check: after each Workspace committed change, debounced
      by about 2 seconds;
  - **account conditions:** sign-in required stops the runtime, and Settings
    shows signed out. `storageLimitReached` shows one account-level notice;
  - **a thrown `StateError`** from the Reconciler is caught, logged with its
    stable code only, shown as an account-level "Sync stopped because of an
    error" notice, and stops automatic checks until the next launch or sign-in.
- **Sync Status per Skill,** derived from the Reconciler's outcomes and the
  links:
  - Device Only (no link), Synced, Waiting to Upload, Applying (while a check
    is working on that Skill), Needs Attention with its reason;
  - shown on the Skill's row and detail page as a small status mark, with
    the reason's text on Needs Attention;
  - Activations are untouched by sync.
- **Start and Stop Syncing:** a "Sync to Cloud" toggle on the Skill detail
  page, calling `startSyncing` and `stopSyncing` through the queue.
- **No resolving actions yet:** Needs Attention only shows the reason here;
  T32 adds the actions.
- All strings in both ARB files.

### Acceptance

- **Runtime tests** with `FakeCloudService`, T29's adapter over a real
  temporary Workspace, and a fake clock:
  - each trigger runs one Feed Check; triggers during a check queue one more,
    not many;
  - a publish runs one local-change check after the debounce;
  - sign-in required stops the runtime; a new sign-in starts it with that
    account's state;
  - a `StateError` stops automatic checks and shows the notice.
- **Status tests:** each Sync Status and each Attention Reason renders, in
  English and Chinese.
- **Two-Device test:** two runtimes over two temporary Workspaces and one
  fake service. A publish on A shows Synced on both after B's next check.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code.

### Scope fence

- **In scope:** `skilldeck-app/lib/features/cloud/`, the Skills list and
  detail views for the status mark and toggle, l10n.
- **Out of scope:**
  - resolving actions and the new-Device activation step (T32);
  - metadata, tags, and Note Conflict (M6);
  - `skills_cloud` and `skills_workspace` changes. If one is needed, stop
    and ask.

### Stop and ask if

- The App has no existing hook for foreground, reconnect, or wake on macOS,
  and adding one needs a new plugin.
- The status mark does not fit the existing Skill row without a design choice.

## Maintained by Codex

### Progress

- [x] Wire the account-scoped runtime, serialized checks and actions, and Workspace shutdown.
- [x] Connect foreground, network reconnect, native macOS wake, and the two-minute scheduler.
- [x] Add per-Skill statuses, the detail toggle, and localized account notices.

### Decision Log

- Use the existing Workspace snapshot revision stream to debounce local changes. The scheduled run retries the Workspace cursor before checking the account feed. `FeedCheckResult.followedBy` preserves both outcomes and the longer `Retry-After`.
- Reconnect uses the approved `connectivity_plus` plugin. An AppKit wake notification uses the existing Runner window to signal Dart. The lifecycle listeners also cover a saved session that is still offline at App launch.
- A 401 from the active runtime clears its saved session through the sign-in owner. A draining runtime cannot read or delete another account's credentials.
- The adapter reports Applying during the Workspace transaction for the affected Skill. Other Skills keep their own status.

### Surprises

### Follow-ups

### Outcome

Focused App verification passed 14 tests with one opt-in service test skipped. It covers trigger coalescence, expired sessions, an account switch during a late 401, a protocol error, quota status, and English and Chinese rendering. A test with two real Workspaces verifies the debounce and cross-Device publication.

Final integrated gates and limits: [M7 validation report](../validation/m7-app-personal-sync-2026-11-27.md).
