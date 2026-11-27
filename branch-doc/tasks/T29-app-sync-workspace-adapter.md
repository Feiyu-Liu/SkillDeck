# ExecPlan: T29 App: the real SyncWorkspace adapter and durable sync state

Milestone M7, part 1. It does not depend on M6, so it can start now. After T27.
Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

The App can build a `Reconciler` over the real Workspace. Its sync state
survives a restart, is kept per account, and holds no credentials.

### Context

- **Read first:**
  - root `CLAUDE.md`, the skilldeck-app architecture: the
    `SkillsWorkspaceRepository` seam, its decorators, and `SkillsManagerRuntime`;
  - `packages/skills_cloud/lib/src/sync/`: `SyncWorkspace`, `SyncStateStore`,
    `PortableSource`, and the fake in `lib/src/testing/`;
  - `../m5-sync-apply-contract.md`;
  - `../reviews/2026-11-27-m4-review.md`, items M4-6 and M4-7.
- **The adapter goes through the App's seam,** not around it. Extend
  `SkillsWorkspaceRepository` with what `SyncWorkspace` needs:
  - `inspectRevisionSelections`;
  - `inspectCommittedChanges`;
  - `exportRevisionPack`;
  - `applyRemoteState` with its variants;
  - the Source Descriptor and Declared Skill Name read;
  - the Slot Key derivation.

  Implement them in `PackageSkillsWorkspaceRepository` and both decorators, so
  that the diagnostics and the ownership gate apply to sync writes too.
- **The App maps `ManagedSkillId` to `WorkspaceSkillId`.** The adapter speaks
  `skills_cloud`'s string IDs. Keep one mapping, at the adapter.

### Contract

- **Dependency:** the App gains a path dependency on `packages/skills_cloud`.
  Update its lockfile; record the command.
- **`WorkspaceSyncAdapter`**, in `lib/features/cloud/data/`, implements
  `SyncWorkspace`:
  - **Source mapping:** each Source Descriptor maps to `PortableSource`, and
    each `PortableSource` maps to a Source Descriptor for Install and Source
    Replacement:
    - Git and Well-known keep their portable fields;
    - Local and Adopted Snapshot map to Device-Bound, with this Device's label
      and a display label, never a path;
    - a Synced Origin Source maps back to exactly the Device-Bound
      `PortableSource` it was installed from (M4-6);
    - a Device-Bound `PortableSource` maps to a Synced Origin Source (T03).
  - **Results:** every Workspace result and error code maps to the port's
    result type. Unknown codes map to `operationFailed`, never to success.
- **`FileSyncStateStore`** implements `SyncStateStore`:
  - one JSON file per account and Device, under the App support directory,
    in a `cloud/` folder;
  - the folder name is a hash of the origin and account ID, never the raw
    account ID or email;
  - writes go to a temporary file in the same folder, are flushed, then
    renamed;
  - a corrupt or unreadable file is moved aside and treated as empty, with a
    typed diagnostic. Sync then bootstraps again, which never re-uploads (R6);
  - it stores no token, URL, email, or `source` contents beyond what
    `SyncLink` already holds.
- **No UI** in this card.

### Acceptance

- **Adapter, through a real Workspace in a temporary directory:**
  - each Source type maps both ways, per the rules above;
  - **M4-6:** install a Device-Bound Lineage through the adapter, read it
    back, and compare with the Lineage's `source`: they are equal;
  - each port operation is called once through the decorator chain. A test
    shows that the ownership gate's refusal reaches the Reconciler as a typed
    failure.
- **Reconciler end to end:** two real Workspaces (two temporary directories)
  and `FakeCloudService` from `package:skills_cloud/testing.dart`:
  - publish on A, check on B, and B has the revision;
  - a Draft on B blocks, and resolving it lets the next check apply;
  - a Source Replacement on A reaches B.

  The fake cannot verify real packs. If needed, add a test-only option to the
  fake that accepts packs without parsing them; record it in the Decision Log.
- **State store:** restart (new instance over the same file) keeps every
  field; two accounts use separate files; a truncated file recovers as empty
  with the diagnostic; a search of the file finds no token or email.
- **M4-7, opt-in:** an integration test that drives `CloudApi` with real packs
  from the adapter against a service origin given by an environment variable.
  It is skipped without the variable. Run it once against `wrangler dev` or
  staging if the maintainer provides a test session, and record the result.
- **Gates:** the App gates from `CLAUDE.md`, and the `skills_cloud` gates, each
  with its own exit code.

### Scope fence

- **In scope:** `skilldeck-app/lib/features/cloud/data/`, the
  `SkillsWorkspaceRepository` seam and its implementations, the App's
  `pubspec.yaml` and lock, and their tests.
- **Out of scope:**
  - UI, Riverpod wiring of the sync runtime, and sign-in (T30, T31);
  - changes to `skills_workspace` or `skills_cloud` behaviour, apart from
    the test-only fake option above.

### Stop and ask if

- The ownership gate or the diagnostic decorator cannot pass a sync write
  without a new rule.
- A Source Descriptor cannot be mapped back exactly (M4-6).
- The App's `ManagedSkillId` mapping hides an ID that the Reconciler needs to
  persist.

## Maintained by Codex

### Progress

- [x] Extend the App repository seam and its package, diagnostics and
  ownership implementations.
- [x] Add the Workspace sync adapter and an account- and Device-scoped file
  store.
- [x] Run the opt-in M4-7 pack round trip against a local Worker.
- [x] Verify source mappings, the ownership gate, and durable state in App
  tests.

### Decision Log

- The maintainer approved representing local Git paths as Device-Bound
  `local` sources. Their absolute paths stay on the Origin Device.
- Device-Bound labels use the common Cloud and Workspace domain of 256
  Unicode scalar values and exclude path separators, colon and C0/C1
  controls. The Cloud parser enforces the common domain.
- The maintainer approved an optional opaque `originSourceId` for
  Device-Bound provenance. The App derives it with HMAC-SHA-256 over the
  local Source Descriptor and a random seed held by that App installation.
  The recipient round-trips the ID and display labels in Synced Origin
  provenance. Older values without an ID remain readable.
- The maintainer approved the local `sourceEpoch` for detecting explicit
  Source Replacement when the entire Source Descriptor stays equal. A
  successful install or replacement returns the epoch it committed.
  Reconciliation remembers it on the local link. An incoming replacement
  guards the old epoch so it can safely replace identical revisions.
- The test fake can carry real pack bytes while retaining the protocol
  checks. The opt-in Worker test exercises actual verification.
- When a restored Workspace invalidates the local cursor, rescan the
  retained committed changes and current Skill IDs. Missing IDs alone
  provide no evidence of an intentional local Removal.

### Surprises

- The public Workspace Skill exposes its Source Descriptor but no
  Source Lineage identity. The portable Device-Bound display label can
  match for distinct absolute paths with the same basename. A macOS
  reproduction replacing one local Source with a same-basename directory
  accepted the local replacement, then hit `cloud_workspace_contract`
  while the Reconciler tried the old Generation's content path.
- Workspace permits Source Replacement at the exact same address. The
  initial commit is deterministic. Replacing identical bytes can produce
  the same revision ID even though Workspace created a new Source Lineage.

### Follow-ups

- Check experimental Lineages created on the Origin Device before
  `originSourceId` when moving an existing development Workspace forward.
  The first reconciliation can advance a Generation to record the new ID.

### Outcome

- The focused App adapter, store and repository suites passed 35 tests,
  with one opt-in skip, exit 0. This covered local Git, ownership refusal,
  Draft blocking and resolution, Source Replacement, and durable state
  recovery.
- After the source identity fix, the focused App adapter and store suites
  passed 8 tests with one opt-in skip. The two real Workspaces converged on
  Generation 2 after replacing a Source with another of the same basename.
  The Workspace codec and Cloud parser suites passed 5 and 2 tests.
- After adding the local Source Epoch, the App adapter, state store and
  runtime suites passed 14 tests with one opt-in skip, exit 0. Two real
  Workspaces converged after same-address replacement with changed bytes and
  with identical bytes. Both peers advanced their Source Epochs, and Cloud
  advanced through Generations 3 and 4.
- The Cloud package's enforced dependency resolution using
  `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile`,
  format check, strict analyzer, and 88-test suite passed with exit 0
  before the final M7 changes. The integrated App and Cloud gates are
  recorded with the batch.
- M4-7 passed on macOS using two temporary Workspaces and the local
  service's workerd test fixture with D1 and R2. The test sent and
  downloaded native Revision Packs through the real Cloud API. The
  test needs `SKILLDECK_CLOUD_TEST_ORIGIN` and an ephemeral
  `SKILLDECK_CLOUD_TEST_TOKEN` in the test process environment.

Final integrated gates and limits: [M7 validation report](../validation/m7-app-personal-sync-2026-11-27.md).
