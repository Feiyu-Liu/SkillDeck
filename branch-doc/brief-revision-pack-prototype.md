# Brief: Revision Pack prototype for SkillDeck Cloud Phase 1

**Date:** 2026-11-23
**From:** the SkillDeck Cloud architecture session
**To:** the agent who ran the Git hosting comparison
**Decision owner:** the maintainer. You prototype and report; you don't decide.

## 1. What changed, and why

Thank you for the hosting comparison (`git-hosting-local-test-results-2026-11-23.md`).
It showed that both Artifacts and standard Git meet our protocol needs. It also
showed that the service would use a Git host only to store bytes and answer
ancestry questions, because the database already holds every Lineage Head.

The maintainer has therefore agreed, subject to this prototype, to drop Git
hosting altogether (**R15** in the revised ADR-0105 proposal). Instead:

- Devices exchange standard Git **pack files** through the Cloud API.
- **R2** stores the packs.
- **D1** holds the commit graph.

Skill repositories are small *(maintainer assessment)*, so Git's negotiation
step isn't worth running a server for. You don't need to finish the Artifacts
versus self-hosted comparison.

This prototype must show whether the design works before anyone builds it.

## 2. Material to read first

| Document | Where | Notes |
| --- | --- | --- |
| ADR-0105 revision proposal: R2, R3, R9, R11, R15 | `0105-revision-2026-11-23-proposal.md`, supplied by the maintainer | **Private.** Never commit it. R15 is the design under test. |
| Your previous results and harness | Your own workspace | Reuse the 500-commit fixture and the libgit2 C client. |
| Existing pack code in the Workspace | `packages/skills_workspace/native/src/revision_engine.c`: `skills_workspace_revision_recovery_pack_create` and `skills_workspace_revision_recovery_pack_restore` | These already write and verify the closure of retained roots for Recovery Bundles. Read them before writing new pack code. |
| Repository guide | `CLAUDE.md`, `AGENTS.md`, `CONTEXT-MAP.md`, `packages/skills_cloud/CONTEXT.md` | Invariants and vocabulary. CONTEXT still uses the retired terms Lineage Repository and retention refs. Follow R15 where the two differ. |

## 3. The design under test (R15, summarised)

- **Head Pack:** one pack holding the complete closure of a head's Effective
  and Upstream commits. Every Upload sends one. There are no incremental packs
  and no pack chains.
- **Upload:**
  1. The Device writes the Head Pack with libgit2.
  2. It uploads the pack to the Worker, which stores it in R2 under the pack's
     SHA-256.
  3. The Worker verifies the pack. It recomputes every object ID and checks
     that the closure of the named commits is complete. It then records each
     commit's parents in D1.
  4. The Device calls Head Advance with the expected head, the new head, and
     the pack's digest. Head Advance is a compare-and-swap that accepts only a
     descendant, using a D1 ancestry query.
- **Download:**
  - The Worker streams the head's pack from R2. There are no signed URLs.
  - The Device indexes it into staging with libgit2, which verifies it again.
- **Sweep:** packs that no head references are deleted after a 24-hour grace.
  Deleting a Generation removes its whole key prefix.
- **Authentication:** a bearer Cloud Session on every request. There are no
  content tokens, and credentials never appear in URLs.

## 4. Questions to answer

1. Does a pack exported by the vendored libgit2 1.9.7 round-trip through a
   Worker, R2 and D1 into another Store with every commit ID identical?
2. **The critical question:** can a Worker verify a Head Pack, with complete
   object hashes and closure completeness, within Worker CPU limits?
   - At what pack size does it stop fitting?
   - Name the library, isomorphic-git or another, and its licence.
3. Does Head Advance behave correctly under concurrency and retries?
4. Can libgit2 import a pack next to a live Store without changing it?
   - Which libgit2 calls does that need: `git_indexer`, `git_odb_write_pack`,
     or something else?
   - How far does the existing recovery restore code get?
5. How big are real Head Packs, and how much upload bandwidth do repeated
   full-closure uploads cost compared with incremental packs?

## 5. Tests and pass criteria

Run everything locally: `wrangler dev` with local R2 and D1 through Miniflare,
plus your C client. Record one line per run, as before. Mark anything you
didn't run as **NOT RUN**, with the reason.

| # | Test | Pass criteria |
| --- | --- | --- |
| P1 | **Round trip.** Device A exports a Head Pack of the 500-commit fixture, with an extra Upstream root on a side history. It uploads the pack and calls Head Advance. Device B, starting from an empty Store, downloads and imports it. | B holds every commit with an ID identical to A's. Every file reads back byte for byte. D1 holds 500+ commit rows with correct parents. |
| P2 | **Worker verification, positive.** Verify the P1 pack in the Worker. | Accepted. Commit IDs and parents extracted from the pack match the fixture. |
| P3 | **Worker verification, negative.** Run each case separately: a truncated pack; a pack with one flipped byte inside an object; a pack missing one blob (build it with `git pack-objects` from an object list); named roots absent from the pack; a pack holding an extra object unreachable from the roots. | Each case is rejected with its own error code, except the unreachable object (see criterion 3). No D1 rows are written and the head doesn't change. For the unreachable object, record whether the reader can detect it. Phase 2 Release Packs must reject such packs, but Phase 1 Head Packs may accept them. |
| P4 | **Verification cost.** Measure Worker CPU time and wall time to verify Head Packs of about 100 KB, 1 MB, 10 MB and 50 MB. Use text-heavy and binary-heavy variants. | Report CPU milliseconds against the documented Worker CPU limits for Free and Paid plans, with the source. A 1 MB pack verified in under 1 s of CPU is a pass. Larger sizes are recorded, not passed or failed. |
| P5 | **Head Advance compare-and-swap.** Run these cases: two concurrent advances from the same expected head; a non-descendant head; a stale expected head; the same advance repeated after a lost response; a head whose pack was never uploaded; a pack from another Generation. | Exactly one concurrent advance wins. The non-descendant, the stale head, the missing pack and the wrong Generation are each rejected with no effect. Repeating an advance already applied returns the same committed state. |
| P6 | **Divergence.** A and B each commit offline from head R. A advances first. B's advance is rejected. B downloads A's Head Pack, merges with libgit2 (two parents), exports a new Head Pack and advances. | B's merge commit has parents A and B. A fast-forwards to it on its next download, and every ID matches. |
| P7 | **Import next to a live Store.** Import a Head Pack into staging beside a Store that already holds most of its objects. Interrupt one import midway. | The live Store is unchanged throughout, checked by hashing its directory before and after. Re-importing objects the Store already has is a no-op. After the interruption, the staging area is either complete or discarded, and a retry succeeds. |
| P8 | **Sweep and deletion.** Leave behind an uploaded pack that was never advanced, and a pack replaced by a newer head. Run the sweep with the grace shortened. Then delete a Generation. | Only unreferenced packs past the grace are deleted. After the Generation is deleted, listing its prefix returns zero keys and D1 holds zero rows for it. |
| P9 | **Sizes and bandwidth.** Measure Head Pack sizes for the fixture and for realistic Skills. The repository has no Skill fixtures, so ask the maintainer for a few representative real Skills, or build ones of typical shape: a `SKILL.md`, a few reference Markdown files and a small script. Then simulate 50 small edits to one Skill, comparing the total upload bytes of full-closure packs with incremental packs (`git_packbuilder_insert_walk`, hiding the previous head). | Report a table. State the history length at which full-closure uploads exceed 1 MB per upload for a typical Skill. |
| P10 | **Authorization.** Send uploads and downloads with no session, with another account's session, and for another account's pack digest. | All are refused without revealing whether the pack exists. No credential appears in any URL, R2 key, D1 row or log line. Search the logs to confirm. |

Use a stub bearer check for P10. Better Auth isn't needed in this prototype.

## 6. Constraints

- **Where code lives:**
  - The prototype Worker is service code. It must **not** be committed to the
    public GPL repository `Feiyu-Liu/SkillDeck`; keep it in your private
    workspace.
  - Client harness code may live on your own branch of SkillDeck, under `tool/`
    or a scratch directory, outside `skills_workspace`'s public API.
  - Don't modify `main` or other people's branches.
- **Data and secrets:** use no real credentials, Cloudflare production accounts
  or user data. Don't put personal or project details in requests to outside
  services.
- **Invariants:** see CLAUDE.md, "Invariants".
  - The Cloud Session never reaches libgit2, SQLite, Store configuration, URLs
    or logs.
  - Imports never write to a live Store directly.
- **Facts to cite:** cite Cloudflare limits and pricing from primary sources,
  with retrieval dates. These include R2 pricing, Worker CPU and request-body
  limits, `DecompressionStream` support, and the R2 bucket jurisdiction
  options. Mark anything you couldn't check as **UNVERIFIED**.

## 7. Deliverable

A Markdown report in the style of your previous one, containing:

- an executive summary that answers the five questions in section 4;
- the P1–P10 results table, with timings and one line of captured output per
  run;
- the Worker pack-reader choice, its licence, and its CPU budget per pack size;
- the libgit2 calls needed for export and staged import, and how much of the
  recovery pack code can be reused;
- a cost sketch for 1k, 10k and 100k active users. Assume 20 synced Skills each
  and a few Uploads per user per day, using measured pack sizes and current R2,
  D1 and Workers pricing, and state your assumptions;
- **blockers**: anything that would force the R15 fallback or a return to Git
  hosting;
- the decisions left for the maintainer.
