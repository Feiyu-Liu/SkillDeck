# ExecPlan: T32 App: Attention Reason actions and the new-Device step

Milestone M7, part 4. After T31. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

Every content Attention Reason offers its actions in the App. A newly
signed-in Mac shows what bootstrap installed and offers to activate it.

### Context

- **Read first:**
  - `packages/skills_cloud/CONTEXT.md`, the Attention Reason table;
  - `Reconciler`'s resolving methods: `keepDeviceOnly`, `removeMissingLocally`,
    `uploadAsNewLineage`, `acceptReplacement`, `replaceOccupied`, `exclude`,
    `include`, and `stopSyncing`;
  - `SyncBootstrap.installedSkillIds`;
  - the App's existing Draft and conflict review screens.
- **R4:** a conflicting Sync Merge becomes an Update Candidate Session. The
  person resolves it in the existing conflict review, not in a new screen.

### Contract

- **Actions per reason,** each run through T31's queue, each asking for
  confirmation where it discards something. They follow the table in
  `packages/skills_cloud/CONTEXT.md`:

  | Reason | Actions |
  | --- | --- |
  | Incoming change waits behind a Draft | publish the Draft, which then Sync Merges; review the incoming difference; discard the Draft (confirm) |
  | Sync Merge conflict | open the existing conflict review, with its keep-this-Device and keep-other-Device shortcuts |
  | Removed on another Device while a Draft exists here | remove here; keep it here as Device Only |
  | Source replaced on another Device while this Device has unsynced revisions | accept the replacement (confirm: local revisions are lost); keep as Device Only |
  | Skill Slot occupied by a different local Skill | replace the local Skill (confirm); keep it and exclude the synced one |
  | Too large to sync | keep as Device Only; Stop Syncing |
  | Missing from the Cloud Library after a reset | remove here (confirm); keep as Device Only; upload it as a new Cloud Lineage |

  "Note Conflict" waits for M6.
- **After an action,** the runtime reconciles that Skill and refreshes its
  status.
- **Device Exclusions:** a "Hidden from this Mac" list in the Cloud section of
  Settings. Each row can be shown again, which calls `include`.
- **New-Device step:** after the first bootstrap for an account on this
  Device, show a one-time sheet listing the installed Skills. The person picks
  which to activate, and for which Agents, using the existing activation
  flow. Bootstrap itself still creates no Activations.
- All strings in both ARB files.

### Acceptance

- **Widget tests,** with T31's runtime over the fakes, one per reason: the
  reason's actions appear, and each action reaches the right Reconciler
  method with the right arguments.
- **Destructive confirmations:** cancelling makes no call.
- **End to end with two runtimes,** for at least:
  - Sync Merge conflict: resolve in the conflict review; both end Synced;
  - Source replaced with unsynced revisions: accept on B; both end Synced on
    Generation 2;
  - Slot occupied: keep and exclude; the excluded Lineage never reinstalls;
    showing it again installs it on the next check.
- **New-Device step:** shown once per account and Device; activating from it
  creates exactly the chosen Activations; dismissing it creates none.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code. The
  macOS desktop E2E suite still passes.

### Scope fence

- **In scope:** `skilldeck-app/lib/features/cloud/`, the Skill detail page,
  Settings' Cloud section, l10n.
- **Out of scope:** metadata and Note Conflict (M6); M8 qualification;
  `skills_cloud` and `skills_workspace` changes. If one is needed, stop and ask.

### Stop and ask if

- The existing conflict review cannot open an Update Candidate Session created
  by a Sync Merge.
- An action's Reconciler method is missing or its result is not enough to
  refresh the status.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
