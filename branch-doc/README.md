# branch-doc

Development documents for SkillDeck Cloud, kept on the
`claude/amazing-keller-unt4dd` branch only.

> **Never merge this folder into `main`.** Before merging this branch, remove
> `branch-doc/` from the merge (for example, delete it in a final commit on a
> copy of the branch, or exclude it when squashing). The branch itself is on a
> public repository, so anything here is publicly readable.

New development documents for this work go in this folder.

## Contents

| File | What it is | Status |
| --- | --- | --- |
| `0105-revision-2026-11-23-proposal.md` | ADR-0105 revision, R1–R17: Distribution model, state-based Personal Sync, Revision Packs, macOS first | Accepted 2026-11-23; ADR-0105 amendment applied in the private docs |
| `cloud-build-vs-adopt-survey.md` | Build-vs-adopt survey for the client and the Cloudflare service | Reference; its Artifacts and WebSocket verdicts are superseded by R8 and R15 |
| `brief-revision-pack-prototype.md` | Brief for the Revision Pack prototype (tests P1–P10) | Run 2026-11-27; see the results report |
| `revision-pack-prototype-results-2026-11-27.md` | Revision Pack prototype results: P1–P10, reader budget, libgit2 calls, cost sketch | P2 and P4 pass. Decided 2026-11-27: R15 as written, 16 MB / 64 MB bound, D1 sharded by account |
| `prototype/revision-pack/device.py` | Device CLI for the prototype, over `skills_workspace`'s private native library. Harness only, not product code | Used by the 2026-11-27 run |
| `handover-phase1-git-hosting.md` | Handover for the Artifacts vs self-hosted Git comparison | Superseded by R15; kept for the record |
| `git-hosting-local-test-results-2026-11-23.md` | Local Git hosting test results | Input to R15 |
| `windows-http-test-plan.md` | Windows HTTP qualification plan | Paused (R17) |
| `windows-http-2026-11-23.md` | First Windows HTTP qualification run | Input to R17 |
| `execplan-template.md` | Template for the ExecPlans handed to Codex, with simplicity rules against over-engineering, and UI rules (added 2026-11-28) | Draft |
| `phase1-plan.md` | Phase 1 (Personal Sync, macOS) plan: goal, binding decisions, components, milestones M1–M8, blockers | Draft |
| `tasks/T01-revision-pack-export.md` | Seam 1: Revision Pack export and the public revision identifier (R16) | Implemented and verified locally |
| `tasks/T02-revision-pack-import.md` | Seam 2: Revision Pack import into staging | Implemented and verified locally |
| `tasks/T03-synced-origin-source.md` | Seam 5: Synced Origin Source descriptor, schema v4 | Implemented and verified locally |
| `tasks/T04-skills-cloud-package-and-feed-check.md` | New `skills_cloud` package and Feed Check scheduling (R8) | Implemented and verified locally |
| `reviews/2026-11-24-m1-m2-review.md` | Review of T01–T04 and re-review of T05 | Items 1–4 and 6 fixed in T05. Item 5 in T16. Item 7 fixed before M5 |
| `tasks/T05-m1-review-fixes.md` | Fixes for review items 1–4 and 6 | Implemented and verified locally |
| `m5-sync-apply-contract.md` | M5 contract: `applyRemoteState` variants, results, and content rules; the committed-change feed | Confirmed 2026-11-24; `RemoteSkillSourceReplacement` added 2026-11-27 (T25); check order and retry wording clarified by the M5 review; current-revision read added 2026-11-24 |
| `tasks/T06-committed-change-feed.md` | Seam 4: committed-change feed, schema v5 | Implemented and verified locally |
| `tasks/T07-apply-remote-content.md` | Seam 3, content: fast-forward, Sync Merge, conflict to Update Candidate Session | Implemented and verified locally |
| `tasks/T10-adr-0105-amendment.md` | Append the revision and the 2026-11-24 decisions to the private ADR-0105 | Applied and verified locally |
| `reviews/2026-11-24-m5-review.md` | Review of T06, T07, T10, and item 7 of the M1–M2 review | Items 1, 2, 4 (partly), and 6 fixed in T11. Item 3 decided: T12. T08 accepted. Item T08-1 (pre-existing Store recovery defect) decided: T13. T13 and T09 accepted; T09 left four Nits. Item T13-1 fixed in T14, accepted. Nits T09-1 to T09-3 and T14-1 fixed in T15, accepted |
| `tasks/T11-m5-review-fixes.md` | Fixes for M5 review items 1, 2, 4 (optional), and 6 | Implemented and verified locally |
| `tasks/T12-inspect-revision-selections.md` | Seam 4: read the current Effective and Upstream `RevisionId` of Skills | Implemented and verified locally |
| `tasks/T08-apply-remote-install.md` | Seam 3, install: create a synced Skill on a new Device from a pack | Implemented, reviewed, and accepted (gates run by Codex on macOS) |
| `tasks/T13-recovery-bundle-roots.md` | Fix T08-1: Recovery Bundles keep every revision that reconciliation retains | Implemented, reviewed, and accepted. T13-1 (remote-only ancestors) decided: T14 |
| `tasks/T09-apply-remote-metadata-removal-vocabulary.md` | Seam 3, the rest: metadata, Synced Removal, and tag vocabulary | Implemented, reviewed, and accepted (gates run by Codex on macOS). M5 complete |
| `tasks/T14-recovery-bundle-history.md` | Fix T13-1: Recovery Bundles carry each retained revision's history, with a roots-only fallback | Implemented, reviewed, and accepted (gates run by Codex on macOS) |
| `tasks/T15-m5-nit-cleanup.md` | Clean up Nits T09-1, T09-2, T09-3, and T14-1 | Implemented, reviewed, and accepted (gates run by Codex on macOS) |
| `cloud-api-contract-v0.md` | M3: Cloud API contract v0, conventions and sign-in. App sign-in with an authorization code and PKCE added 2026-11-28 (R14 amended); Device Authorization kept for clients without a browser window. Library, pack, and feed endpoints come in v0.1 with M4 | Draft; code lifetime decided 2026-11-26 (10 minutes); HTTP 429 added 2026-11-27 (T19). Service side: T17 |
| `cloud-api-contract-v0.1.md` | M4: Personal Sync data API: Cloud Library, Lineages and Generations, Head Packs, Head Advance, Removal and Stop Syncing, Account Change Feed | Accepted 2026-11-27, open points decided |
| `cloud-api-contract-v0.2.md` | M6: Personal Sync metadata, Synced Tag Vocabulary, and Note Conflict | Accepted for M6 implementation on 2026-11-27 |
| `tasks/T16-device-sign-in-client.md` | M3: Device Authorization sign-in client in `skills_cloud`, and M1–M2 review item 5 | Implemented by Claude (gates on Linux x64) |
| `tasks/T17-service-device-sign-in.md` | M3, service side: contract v0 sign-in on `wrangler dev`. Runs in the private service repository | Implemented in the service repository (`9de140b`), reviewed, and accepted; follow-ups T18 and T19 |
| `reviews/2026-11-27-m3-review.md` | Review of T17, with T16 driven against the dev service | T17 accepted. T17-1 and T17-3: T18. T17-2 fixed in T19 |
| `tasks/T18-service-approval-rate-limit.md` | Fix T17-1 (approval page limit) and T17-3 (lockfile registry). Runs in the private service repository | Implemented in the service repository, reviewed, and accepted |
| `tasks/T19-contract-429.md` | Fix T17-2: HTTP 429 in contract v0 and the sign-in client | Implemented by Claude (gates on Linux x64) |
| `tasks/T20-service-library-and-feed.md` | M4 service 1/2: account-sharded Lineages, library, ending, feed, Device description on sessions. Runs in the private service repository | Implemented in the service repository, reviewed, and accepted |
| `tasks/T21-service-packs-and-head-advance.md` | M4 service 2/2: Head Packs, Head Advance, Generation change, retention. After T20 | Implemented in the service repository, reviewed, and accepted. Staging deployed for email sign-in |
| `tasks/T22-client-api-and-fake-service.md` | M4 client 1/3: v0.1 API client and an in-memory fake service | Implemented, reviewed, and accepted (gates run by Codex on macOS) |
| `tasks/T23-client-reconciliation.md` | M4 client 2/3: Reconciliation, Upload, Download, Removal and Stop Syncing for linked Skills. After T22 | Implemented, reviewed, and accepted; M4-1 to M4-5 go to T27 |
| `tasks/T24-client-bootstrap-and-reset.md` | M4 client 3/3: new-Device bootstrap, reset, Device Exclusions. After T23 | Implemented, reviewed, and accepted |
| `tasks/T25-apply-remote-source-replacement.md` | Workspace: `RemoteSkillSourceReplacement`, applying a remote Generation change (decided 2026-11-27) | Implemented, reviewed, and accepted (gates run by Codex on macOS) |
| `tasks/T26-client-generation-change.md` | M4 client: Generation change in both directions. After T23; needs T25's contract only | Implemented, reviewed, and accepted |
| `validation/m4-client-workspace-2026-11-27.md` | Codex's gate results and coverage for T22–T26 | Record |
| `reviews/2026-11-27-m4-review.md` | Review of T18 and T20–T26 | Accepted. M4-1 to M4-5: T27. M4-6 for the M7 adapter. M4-7 for the maintainer |
| `tasks/T27-m4-review-fixes.md` | Fix M4-1 to M4-5 in the Reconciler | Implemented and verified locally; see the M7 validation report |
| `tasks/T28-contract-v0.2-metadata.md` | M6: Codex drafts contract v0.2 for metadata, tags, and Note Conflict. Design only | Draft accepted and revised; implementation in T33/T34 |
| `tasks/T29-app-sync-workspace-adapter.md` | M7 1/4: the real `SyncWorkspace` adapter through the App seam, and durable per-account sync state. Covers M4-6 and an opt-in M4-7 | Implemented and verified locally, including real Worker pack round trip |
| `tasks/T30-app-cloud-sign-in.md` | M7 2/4: Cloud sign-in in Settings, secure session storage, `cupertino_http`, Cloud off without an origin or off macOS | Implemented and verified locally; manual staging sign-in not run |
| `tasks/T31-app-sync-runtime-and-status.md` | M7 3/4: the serialized sync runtime, Feed Check triggers, per-Skill Sync Status, Start and Stop Syncing | Implemented and verified locally |
| `tasks/T32-app-attention-actions-and-bootstrap.md` | M7 4/4: actions for every content Attention Reason, Device Exclusions in Settings, the new-Device activation step | Implemented and verified locally, including approved Workspace review extensions |
| `validation/m7-app-personal-sync-2026-11-27.md` | Final T27–T32 scope, approvals, gates, coverage and acceptance limits | Record |
| `tasks/T33-service-metadata.md` | M6 service: metadata CAS, Note Conflict, tag identity and bounded Feed/library projection | Implemented and verified locally; see M6 validation |
| `tasks/T34-metadata-reconciliation-and-app.md` | M6 client, guarded Workspace metadata and macOS App integration | Implemented and verified locally; see M6 validation |
| `validation/m6-metadata-sync-2026-11-28.md` | M6 implementation, final gates and remaining acceptance boundaries | Record |
| `tasks/T35-service-app-sign-in.md` | App sign-in, service side: `/app/sign-in` and `/app/token` with an authorization code and PKCE (R14 amended 2026-11-28). Runs in the private service repository | Ready for Codex in the service repository |
| `tasks/T36-client-app-sign-in.md` | App sign-in, client side: `signInWithBrowser` over a web-authentication port | Ready for Codex; can run in parallel with T35 |
| `tasks/T37-app-sign-in-window.md` | App sign-in, App side: the system sign-in window, with exact states and text; Device Authorization removed from the App | Ready for Codex, after T36 |
| `tasks/T38-device-bound-source-identity.md` | Fix from the 2026-11-28 spot check: renaming a Mac started a Generation change for every Device-Bound Skill | Ready for Codex |
| `tasks/T39-cloud-ui-screenshot-audit.md` | Screenshots and an inventory of every Cloud UI state, flagged against the UI rules; no fixes | Ready for Codex; rework cards follow its review |
