# SkillDeck Cloud Phase 1 plan: Personal Sync on macOS

Status: draft, 2026-11-24. Source of truth for decisions: the accepted ADR-0105
revision (`0105-revision-2026-11-23-proposal.md`, R1–R17). This plan only says
what to build, in what order, and what stops work. It does not re-argue the
decisions.

## How to use this plan

- Work is handed out as task cards in `tasks/`, written from
  `execplan-template.md`. Start from the card, not from this plan.
- Repository rules come first: `AGENTS.md` (including the Cloud tripwires),
  `CLAUDE.md`, `CONTEXT-MAP.md`, the root `CONTEXT.md` for Skill Workspace
  vocabulary, and `packages/skills_cloud/CONTEXT.md` for Cloud vocabulary.
- Where a card is silent, decide within those rules and record the choice in
  the card's Decision Log. Where a decision below or a blocker applies, stop and
  ask.
- This branch is on a public repository. Write nothing here that should stay
  private: no credentials, internal hostnames, or personal data.

## Goal

A signed-in person can choose Skills to sync on one Mac and see them, with their
history, metadata, and tags, on another Mac. Changes made on either Mac reach
the other through state Reconciliation. Every Sync Status that is not Synced or
Device Only either clears on reconnect or carries an Attention Reason the person
can resolve.

Phase 1 delivers (R13): Device Authorization sign-in; the Cloud Library, Head
Pack storage, and the Commit Graph; Head Advance; the Account Change Feed and
Feed Checks; Reconciliation, metadata, and the tag vocabulary; per-Skill Sync
Status with every R10 Attention Reason; new-Device bootstrap; Workspace seams
1–4 and the Synced Origin Source.

## Non-goals

- Cloud on Windows. Windows builds ship without a service origin (R17).
- Individual Sharing, Team Distribution, the Marketplace, and the Cloud Release
  Source (Phases 2–4).
- Any realtime channel: no WebSockets, no Durable Objects (R8).
- Syncing Activations or Drafts (decision 10).
- A client outbox, receipt windows, or any other exactly-once bookkeeping (R3).
- Incremental packs or pack chains (R15).

## Decisions to hold

Each line is binding. The R number points to the full text.

- **Reconciliation (R3):** compare local Effective Revision L with the Lineage
  Head R. L = R: nothing. L ancestor of R: Fast-forward Apply. R ancestor of L:
  Upload a Head Pack, then Head Advance expecting R. Otherwise: Divergence,
  resolved by a Sync Merge from the real common ancestor. Pending work is
  derived from state; a lost response resolves at the next Reconciliation.
- **What applies without asking (R4):** fast-forwards, Synced Removal,
  Generation changes, and clean Sync Merges. A conflicting Sync Merge becomes an
  Update Candidate Session. A Dirty Draft or Update Candidate Session blocks
  incoming content for that Skill only.
- **Metadata (R5):** every synced value has a Field Version and every write is
  a compare-and-set. Favorites, tag assignments, tag names, and tag colors
  settle in server order (colors added 2026-11-25). Concurrent Note edits
  form a Note Conflict that keeps both texts.
- **Workspace boundary (R9, R11):** `skills_workspace` gains exactly seams 1–5
  and does no cloud network I/O. Its public API never gains reservation or
  outcome-inspection operations, URLs, credentials, cloud identifiers, Field
  Versions, or Sync Status.
- **Revision identity (R16):** the seams name revisions with an opaque public
  identifier whose string form is the commit ID. Callers never parse it.
- **Revision Packs (R15):** each Upload sends one Head Pack with the full
  closure of the new head's Effective and Upstream commits, addressed by
  SHA-256. The service verifies a pack before any Head Advance may use it.
  Built as written: the prototype passed P2 and P4 (maintainer, 2026-11-27).
- **Head Pack size bound (decided 2026-11-27):** at most 16 MB packed and
  64 MB inflated. The service rejects a larger upload with a typed error. The
  client checks the packed size before uploading.
- **D1 layout (decided 2026-11-27):** the Commit Graph and Lineages are
  sharded by account from the start.
- **Change delivery (R8):** Devices learn of changes only through Feed Checks
  of the Account Change Feed, on launch, foreground, reconnect, wake, and every
  2 minutes. Pack storage is never polled.
- **Sync Status (R10):** derived per Skill as Device Only, Synced, Waiting to
  Upload, Applying, or Needs Attention, shown on the Skill. The seven Attention
  Reasons and their actions are in R10's table.
- **Sign-in (R14):** Device Authorization (RFC 8628) only. The App never
  collects a password or OTP, never opens a loopback listener, and never
  registers a URL scheme. The Cloud Session lives only in platform secure
  storage.
- **Service origin (R16):** chosen per build through `--dart-define-from-file`.
  A build without an origin has Cloud off.

## Components

| Component | Where | Phase 1 responsibility |
| --- | --- | --- |
| Skill Workspace seams | `packages/skills_workspace/` | Seams 1–5 (R11) and the public revision identifier (R16) |
| Cloud client | `packages/skills_cloud/` (new, pure Dart) | Sign-in, Cloud API client over `package:http` `Client`, Feed Checks, Reconciliation, metadata, Sync Status |
| App integration | `skilldeck-app/lib/features/cloud/` | Inject `cupertino_http`, secure session storage, Settings sign-in, Sync Status on Skills, Attention Reason actions, new-Device activation step |
| Cloud service | separate private repository (ADR-0116) | Not built here. This repository depends only on its API contract |

Existing code to build on:

- Recovery pack path, for seams 1 and 2: `createRecoveryPack` and
  `restoreRecoveryPack` in
  `packages/skills_workspace/lib/src/application/runtime/revision_engine_port.dart`,
  through `lib/src/native/revision_worker/` and
  `lib/src/native/revision_engine/revision_native_engine.dart`, down to
  `skills_workspace_revision_recovery_pack_create` and `..._restore` in
  `native/src/revision_engine.c`. The current caller is
  `lib/src/composition/revision_recovery_bundle_publisher.dart`.
- An existing export-to-path read operation, for the shape of seam 1:
  `exportSkillDriftArtifact` in `lib/src/api/skills_repository.dart`.
- Provenance, for seam 5: `lib/src/domain/source_descriptor.dart`,
  `lib/src/infrastructure/database/source_descriptor_codec.dart`, and the
  `updateUnsupported` path for Adopted Snapshot Sources in
  `lib/src/application/source/source_acquisition_coordinator.dart`.
- The App already depends on `flutter_secure_storage` 11.0.0.

## Milestones

Ordered by dependency. Dates are not part of this plan.

| Milestone | Content | Can start |
| --- | --- | --- |
| M1 | Workspace seams 1, 2, and 5 with the revision identifier: T01–T03 | Now |
| M2 | `skills_cloud` package and Feed Check scheduling: T04 | Now |
| M3 | Cloud API contract v0 and Device Authorization sign-in. Contract: `cloud-api-contract-v0.md`; cards T16 (client) and T17 (service) | Now: the contract is drafted here and the service implements it |
| M4 | Reconciliation, Upload, and Download against an in-memory fake of the API | Now: the prototype decision is made (2026-11-27). Contract v0.1 first |
| M5 | Seams 3 and 4: the Sync apply contract and the committed-change feed. Contract: `m5-sync-apply-contract.md`; cards T06, T07, T11 (review fixes), T12 (current-revision read), T08, T13 (Recovery Bundle fix), T09, then T14 (Recovery Bundle history) | After M1 |
| M6 | Metadata, tag vocabulary, and Note Conflict | After M4 and M5 |
| M7 | App integration, Sync Status, every Attention Reason, new-Device bootstrap | After M6 |
| M8 | macOS qualification, including two Devices updating the same Git Source while offline (R3) | After M7, with staging up |

Task cards for M3 onward are written when their milestone is next.

## Blockers

Codex never decides these. If a task reaches one, stop and ask.

| Item | Blocks | Decided by |
| --- | --- | --- |
| Revision Pack prototype, P2 and P4: R15 as written, or its fallback (R16 rule) | M4 | **Decided 2026-11-27:** R15 as written, a 16 MB / 64 MB Head Pack bound, and D1 sharded by account (`revision-pack-prototype-results-2026-11-27.md`) |
| Production API hostname | Persisting any Cloud Session, Cloud Lineage mapping, or Cloud descriptor | **Decided 2026-11-24:** `cloud.skilldeck.cc`, one origin for the Cloud API, Better Auth, and `/device`. Staging is `cloud-staging.skilldeck.cc` |
| Email OTP provider; owner and callback domain of the GitHub OAuth app | M3 end-to-end | **Decided 2026-11-24:** Resend for email OTP. A GitHub organization owns one OAuth App per environment, with callbacks on that environment's origin |
| Private service repository and the Cloudflare dev and staging account | M3 | **Resolved 2026-11-24:** both exist |
| Before beta: data region, quotas, backup, Privacy Policy text, account deletion, pack size bound | Beta | Maintainer |

## The earlier prototype branch

`feat/cloud-personal-sync-20261115` is not merged and is not a base for this
work.

- **May be reviewed and carried over:** the secure session store and the HTTPS
  transport bounds.
- **Discarded:** the intent outbox, receipts and echoes, reservation and
  outcome-inspection APIs, the staged inbox, scope incarnation fences, native
  cloud push and fetch, and the PKCE loopback sign-in.
- Its Workspace schema v4 is not reused.

Do not copy code from that branch wholesale. When a card allows a carry-over,
bring the smallest part and say so in the Decision Log.

## Schema versions on this branch

The Workspace schema was at v3 when this plan started. T03 added v4 and T06
adds v5. Each task that needs a schema change adds the
next version with its own migration and migration test. Never edit a migration
that is already committed.

## Review checklist

Before a task's work is accepted:

1. The card's gates pass, and its Outcome section is filled in.
2. No `AGENTS.md` Cloud tripwire is hit.
3. Every abstraction, file split, or dependency in the Decision Log is
   justified by the card's Acceptance.
4. The diff stays inside the scope fence, or the card says why not.
