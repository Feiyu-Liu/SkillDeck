# ExecPlan: T34 Metadata reconciliation and macOS App integration

## Set by the planner

### Goal

Implement the accepted v0.2 contract end to end for this task's scope.
The maintainer approved the complete M6 plan and its six product decisions
on 2026-11-27. The exact wire contract is ../cloud-api-contract-v0.2.md.

### Scope

skills_cloud metadata API/models/state/reconciliation; Workspace local revision guard; App seam/decorators, durable state, runtime, UI and l10n. No new infrastructure or Windows Cloud.

### Contract

Follow the revised v0.2, the approved M5 local guard addition and existing
repository boundaries. No infinite Note history, receipt window or operation
outbox. Preserve unrelated dirty files. Do not commit, push or deploy.

### Acceptance

Prove all initialization modes, local edit guards, lost responses, account isolation, quota/size actions, third Note text retention, old-service fallback and independent content/metadata attention. Run package and App gates, Workspace 85% coverage, real Worker integration and macOS desktop E2E.
Record command exit codes, evidence scope and any skipped external gates.

### Stop and ask if

An accepted user-data policy cannot be preserved, a new infrastructure
service/dependency is required, or credentials would cross the Workspace seam.

## Maintained by Codex

### Progress

- [x] Accepted contract implemented.
- [x] Focused and integrated local gates completed; see the final evidence below.

### Decision Log

### Surprises

### Follow-ups

### Outcome

- Dart client implements v0.2 metadata bootstrap and Feed Check while preserving
  the existing content cursor on upgrade. It samples guarded Workspace snapshots
  before applying fields, retains unresolved local Notes across restart, and
  derives vocabulary retries from durable tag mappings and current Workspace
  values. At first association the edited cloud assignment set replaces old
  local assignments. The local tag entries and concurrent assignments are
  preserved. A rename cycle updates the local names in one Workspace
  transaction so existing assignments keep their Tag IDs.
- In `packages/skills_cloud`, formatting, strict analysis, and
  `dart test -j 1 --coverage=coverage` exited 0. The suite passed 125 tests
  including 33 new metadata regressions. Production line coverage was 91.85%
  (2,570 of 2,798 lines, excluding testing helpers). See local reports
  `coverage/m6-client-test.log` and `coverage/m6-client.info`.
- Note resolution keeps the locally saved choice when the recovery read fails.
  A 401 reaches the App sign-in handler, and a Retry-After delays both manual
  Note retries and automatic checks. Ten focused App runtime tests passed.
- A reset after server rollback preserves the last agreed local Note when the
  restored text differs. Equal text settles without review. Confirmed lower Tag
  versions reconcile against current server values, keeping local changes
  eligible for compare-and-set.
- The vocabulary stops new create requests after the first quota reply in a pass.
  It still reconciles mapped tags and known duplicates, and retries on later checks.
- Switching back to an account resumes its eligible tags that still exist
  locally. Tags created under another account remain local until assigned to a
  synced Skill. The focused App runtime suite passed 11 tests.
- Transient metadata failures expose waiting Skill IDs independently of the
  latest content result. A settled retry or unlink clears the waiting state.

Final integrated evidence: [M6 validation](../validation/m6-metadata-sync-2026-11-28.md).
