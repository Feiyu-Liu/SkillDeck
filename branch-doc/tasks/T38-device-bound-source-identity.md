# ExecPlan: T38 Renaming a Mac must not start a Generation change

Fixes a finding from the 2026-11-28 spot check of T27–T34: a label change on a
Device-Bound Source is treated as a Source Replacement. Client and App
adapter only. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

Renaming the Mac, or any other change to a Device-Bound Source's labels, leaves
every synced Skill Synced, with no Generation change and nothing applied on
other Devices. A real Source Replacement still starts a Generation change.

### Context

- **The defect:**
  - `WorkspaceSyncAdapter` builds a local or Adopted Snapshot Source's
    Device-Bound `PortableSource` with `originDeviceLabel` set to the Mac's
    current computer name (`workspace_sync_adapter.dart`, the Device-Bound
    branch; the label comes from `cloud_sync_providers.dart`).
  - `Reconciler` compares whole `PortableSource` values (`reconciler.dart`:
    the synced check, `sourceChanged`, the re-read after upload, and the
    bootstrap exact match).
  - `PortableSource ==` compares the full JSON, labels included.
  - So after a rename, every Device-Bound Skill on that Mac looks replaced:
    the next check uploads a new Generation, and every other Device applies a
    Source Replacement, or gets "Source replaced on another Device while this
    Device has unsynced revisions".
  - The display label can fall back to the Declared Skill Name, so it has the
    same problem.
- **Read first:**
  - `packages/skills_cloud/lib/src/sync/portable_source.dart`;
  - the Reconciler's source comparisons and Source Epoch use;
  - `skilldeck-app/lib/features/cloud/data/workspace_sync_adapter.dart` and
    `cloud_device_identity.dart`;
  - `../validation/m7-app-personal-sync-2026-11-27.md`, on `originSourceId` and
    Source Epochs.
- **The rule:** labels are for display. A Device-Bound Source's identity is
  its `originSourceType` and `originSourceId`. An explicit Source Replacement
  is already detected by the Source Epoch.

### Contract

- **`PortableSource.sameSourceAs(PortableSource other)`:** a new method.
  - Two Device-Bound Sources that both have an `originSourceId` are the same
    when `originSourceType` and `originSourceId` are equal. Labels are
    ignored.
  - In every other case it is `==`, as today. This keeps the accepted
    behaviour for legacy values without an ID.
  - `==` and `hashCode` stay as they are.
- **Reconciler:** every place that decides whether the Source changed, or
  whether a local Skill matches a Lineage, uses `sameSourceAs`. Name each one
  in the Decision Log.
- **Labels sent to the service:** create and Generation change keep sending the
  current local labels. A label change alone sends nothing. Other Devices may
  show the old labels until the next real Generation change; record that as a
  Follow-up, not as work here.
- **Source ID stability:** confirm, with a test for each, that
  `sourceIdFor` gives the same ID for one Skill across:
  - a Mac rename;
  - an App restart;
  - a publish of new content;
  - a Declared Skill Name change.

  If any of these changes the ID, stop and ask.

### Acceptance

Tests with the fakes, plus one with T29's adapter over a real temporary
Workspace:

- **Rename:** A syncs a local-path Skill; A's device label changes; the next
  check on A ends Synced, with the Lineage still at Generation 1 and no
  upload. B's next check changes nothing.
- **Display-label fallback:** the same, when only the display label changes.
- **Real replacement:** a local Source Replacement on A still starts
  Generation 2 and reaches B.
- **Legacy:** a Device-Bound value without `originSourceId` behaves exactly as
  before.
- **Bootstrap:** after a reset on a renamed Mac, an exact match by
  `sameSourceAs`, Slot Key, and content links instead of installing a second
  copy.
- **`sameSourceAs`:** unit tests for each case of the rule.
- **Gates:** the `skills_cloud` gates and the App gates from `CLAUDE.md`, each
  with its own exit code.

### Scope fence

- **In scope:**
  - `packages/skills_cloud/lib/src/sync/`;
  - `skilldeck-app/lib/features/cloud/data/`;
  - their tests.
- **Out of scope:**
  - updating labels on the service or on other Devices;
  - `skills_workspace`;
  - the service;
  - UI.
- **Expected size:** about 4–8 files, 200–500 lines including tests.

### Stop and ask if

- A Device-Bound value that this App wrote can lack an `originSourceId`.
- `sameSourceAs` would make two different local Sources on one Mac match.

## Maintained by Codex

### Progress

- [x] Implemented all four source-identity comparisons and verified device/display label changes, bootstrap, legacy Generation behavior, real Source Replacement and real Workspace identity stability.

### Decision Log

- Comparisons changed: synced short-circuit, sourceChanged generation decision, post-upload reread, bootstrap exact match. Maintainer accepted legacy Synced Origin values without IDs retaining full-value equality. Draft publish rejects declared-name changes; a read-only repository fixture tests changed name/fallback labels without changing Workspace domain rules.

### Surprises

### Follow-ups

- Display labels on other Devices stay unchanged until a real Generation change, per the card.

### Outcome

Package and App gates passed with the agreed analysis scope. Fake Reconciler cases explicitly prove no upload/no apply for both labels and preserved legacy behavior; a real temporary Workspace verifies rename, seed reload, publish and bootstrap. No Workspace or service domain code changed. See ../validation/t35-t39-2026-11-28.md.

Changes are committed separately by task; no push or deployment is included.
