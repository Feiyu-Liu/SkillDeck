# ExecPlan: T33 Service metadata, vocabulary and Note Conflict

## Set by the planner

### Goal

Implement the accepted v0.2 contract end to end for this task's scope.
The maintainer approved the complete M6 plan and its six product decisions
on 2026-11-27. The exact wire contract is ../cloud-api-contract-v0.2.md.

### Scope

Private service repository: personal-sync routes, account-shard migration, existing fixture and tests. Do not deploy or change auth/pack transport.

### Contract

Follow the revised v0.2, the approved M5 local guard addition and existing
repository boundaries. No infinite Note history, receipt window or operation
outbox. Preserve unrelated dirty files. Do not commit, push or deploy.

### Acceptance

Prove atomic CAS/feed writes, creation aliases through lifecycle races, note pair preservation, byte-bounded pagination, v0.1 migration/cursor compatibility, account isolation and redaction in workerd. Run complete service tests, typecheck and format.
Record command exit codes, evidence scope and any skipped external gates.

### Stop and ask if

An accepted user-data policy cannot be preserved, a new infrastructure
service/dependency is required, or credentials would cross the Workspace seam.

## Maintained by Codex

### Progress

- [x] Accepted contract implemented.
- [x] Focused and integrated local gates completed; see the final evidence below.

### Decision Log

- Cursor validation and page selection use the same D1 batch snapshot.
- Ended tag private payload is scrubbed while compact identity aliases remain.

### Surprises

### Follow-ups

### Outcome

- Service full suite: 460 passed; Personal Sync suite: 18 passed.
- Typecheck, formatting, Worker build and both disposable local shard migrations passed.
- No live migration, deployment, credentials or unrelated VM evidence changed.

Final integrated evidence: [M6 validation](../validation/m6-metadata-sync-2026-11-28.md).
