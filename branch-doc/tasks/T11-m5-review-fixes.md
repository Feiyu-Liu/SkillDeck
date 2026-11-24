# ExecPlan: T11 Fixes from the M5 review

Milestone M5. Fixes items 1, 2, 4 (optional), and 6 of
`../reviews/2026-11-24-m5-review.md`. Builds on T06 and T07. Contract:
`../m5-sync-apply-contract.md`. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

Remote apply keeps its behaviour, but the generic operation layer no longer
knows about it by name, and real failures are recorded again. T08 and T09 can
then reuse the same path without adding branches.

### Context

- The four branches are listed in review item 1:
  `operation_coordinator.dart:234`, `:376`, `:408`, and
  `drift_operation_control_plane.dart:902`.
- They exist for two reasons:
  - `noChange` and `draftResolutionRequired` are returned by throwing out of
    `prepareCandidate` in `remote_content_command.dart`, which rolls the
    envelope back and would otherwise write a failed Operation Record;
  - remote objects reach the live Store only in the applying phase, so
    reference reconciliation right after sealing would see missing objects.
- The contract now checks L = R and "R is an ancestor of L" before the Draft
  check (Content rules, rule 1).

### Contract

No public API change.

- **Generic layer:** `OperationCoordinator` and `DriftOperationControlPlane`
  contain no reference to a specific `WorkspaceOperationKind`. How the
  behaviour is expressed is up to you. Prefer the smallest mechanism, and
  record it in the Decision Log.
- **Operation Records:**
  - `noChange` and `draftResolutionRequired` leave no Operation Record and no
    journal;
  - a remote apply that fails or is cancelled leaves a record, as every other
    operation does.
- **Order:** an apply where L = R, or where R is an ancestor of L, returns
  `noChange` even when the Skill has a Dirty Draft or an Update Candidate
  Session. The guard still runs first.
- **Optional (review item 4):** decide L = R before copying the live Store.
  Do it only if it stays small.

### Acceptance

- Searching the two generic files for `WorkspaceOperationKind.` finds nothing.
- New tests through the public API:
  - `noChange` and `draftResolutionRequired` leave the operation history and
    the journal table unchanged;
  - a cancelled apply and an apply with a malformed pack each add one failed
    or cancelled record;
  - L = R with a Dirty Draft returns `noChange`.
- All existing T06 and T07 tests, including the crash and recovery tests,
  pass unchanged, or the Decision Log says why one changed.
- T06's Progress has its last item ticked, with the full-suite result.
- **Gates:** the T01 gates. Native code should not change; if it does,
  `dart run tool/regenerate.dart` must leave a clean tree.

### Scope fence

- **In scope:** `packages/skills_workspace/`, and T06's and T11's maintained
  sections.
- **Out of scope:**
  - T08 and T09 variants;
  - a public read of the current Effective (review item 3, still open);
  - the native layer;
  - schema changes.
- **Expected size:** about 5–10 files, 150–400 lines including tests.

### Stop and ask if

- Removing the branches needs a new journal phase, a new recovery entry kind,
  or a schema change.
- Moving the L = R check ahead of the Draft check changes any existing T07
  test other than by adding cases.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
