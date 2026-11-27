# Revision Pack prototype: results (2026-11-27)

**Brief:** `brief-revision-pack-prototype.md` (P1–P10). **Run by:** Claude, in a
cloud session on Linux x64, with the maintainer's go-ahead. **Decision owner:**
the maintainer, under the R16 decision rule. This report states results and a
recommendation; it decides nothing.

**Where the code is:**
- Device CLI (client harness):
  `prototype/revision-pack/device.py` on this branch.
- Worker, verifier, schema, and harness: `spikes/revision-pack/` on branch
  `spike/revision-pack-prototype` of the private service repository. They are
  not reproduced here.

## Executive summary

**P2 passes and P4 passes, so under R16 R15 can be built as written.** One
condition comes with that, and it is about memory, not CPU.

1. **Round trip:** yes.
   - A Head Pack exported by the vendored libgit2 1.9.7 went through the
     Worker, R2, and D1 into an empty Store. All 500 commit IDs were
     identical, every file read back byte for byte, and D1 held 500 commit rows
     with the right parents (P1).
2. **Worker verification:** yes, well inside the CPU budget for real Skills.
   - **Library:** the service repository's own bounded pack reader
     (`parsePack`, part of the service code, so no third-party licence), plus a
     closure walk of about 150 lines. It recomputes every object ID and checks
     that the closure of the named roots is complete.
   - **CPU:** a 0.9 MB pack verifies in about 40 ms of CPU, against a 1 s pass
     line.
   - **Where it stops fitting:**
     - On Workers Free (10 ms CPU per request), it stops fitting at about
       0.1 MB.
     - On Workers Paid (30 s CPU by default), CPU is not the limit: an 8 MB pack
       takes about 0.3 s, and a 40 MB pack about 1.1 s.
     - What does limit it is the **128 MB isolate memory**. The reader keeps
       the pack and every inflated object in memory. A 52 MB binary pack needs
       about 105 MB, which is at the limit. A 40 MB text pack inflates to
       264 MB and needs about 300 MB, which does not fit.
   - **Real Skills are far below both limits.** A typical Skill's Head Pack is
     3 KB new and about 200 KB after 500 edits.
   - isomorphic-git 1.44.13 (MIT) was measured as an alternative. It costs 3.5
     to 9.5 times more CPU and needs a filesystem.
3. **Head Advance:** yes.
   - **Concurrency:** in 10 of 10 concurrent rounds, exactly one of two
     advances from the same head won. The loser got `staleHead`.
   - **Rejections, with no effect:**
     - a non-descendant head;
     - a stale expected head;
     - a pack that was never uploaded;
     - a pack from another Generation.
   - **Retries:** repeating an advance that was already applied returns the
     same committed state (P5).
4. **Import next to a live Store:** yes, with the entry points the Workspace
   already has.
   - `git_indexer` writes into staging. `git_odb_add_disk_alternate` then
     checks the closure against the live Store, which it opens read-only.
   - The live Store's hash did not change through a normal import, a re-import
     (a no-op), or an import killed midway. After the killed import, discarding
     staging and retrying worked (P7).
5. **Sizes and bandwidth:**
   - **Size:** a typical Skill's Head Pack grows by about 0.38 KiB per edit:
     22 KiB after 50 edits, 382 KiB after 1,000, and 763 KiB after 2,000.
     Uploads would pass 1 MB each only after about 2,700 edits.
   - **Full closure versus incremental:** for 50 edits, full-closure uploads
     cost 9 times the bytes of incremental packs. In absolute terms that is
     633 KiB against 67 KiB over 50 uploads.

**No blocker** forces the R15 fallback or a return to Git hosting. Three
decisions are left to the maintainer; see the end of this report.

## Results

All runs are local: workerd through Miniflare, with local D1 and R2, and the
Device CLI over libgit2 1.9.7. One line per run, from `results.json`. **CPU** is
Node's `process.cpuUsage()` running the same verifier; see Method below.

| # | Result | Time | Captured output |
|---|---|---:|---|
| P1 | PASS | 755 ms | pack 197859 B (export 134.5 ms); upload 200; advance 200; B commits 500/500 identical=true; files byte-identical=true; D1 commit rows 500, parents match=true; import 48.4 ms |
| P2 | PASS | 42 ms | workerd verify 200 commits=500 objects=1842; extracted IDs and parents match fixture=true; unreachable=0 |
| P3 | PASS | 8 ms | truncated in transit (address is the full pack's digest): 422 digestMismatch; D1 rows +0; head unchanged=true |
| P3 | PASS | 8 ms | truncated at the source: 422 packChecksum; D1 rows +0; head unchanged=true |
| P3 | PASS | 96 ms | truncated, trailer recomputed: 422 inflateLimit; D1 rows +0; head unchanged=true |
| P3 | PASS | 11 ms | one flipped byte at the source: 422 packChecksum; D1 rows +0; head unchanged=true |
| P3 | PASS | 42 ms | one flipped byte, trailer recomputed: 422 inflateLimit; D1 rows +0; head unchanged=true |
| P3 | PASS | 89 ms | missing one blob: 422 missingObject; D1 rows +0; head unchanged=true |
| P3 | PASS | 43 ms | named roots absent: 422 missingRoot; D1 rows +0; head unchanged=true |
| P3 | PASS | 6 ms | wrong digest address: 422 digestMismatch; D1 rows +0; head unchanged=true |
| P3 | PASS | 61 ms | extra unreachable object: 200 accepted, unreachableObjects=1; D1 rows +500; head unchanged=true |
| P4 | INFO | 10 ms | text 100 KB: pack 0.10 MB, 132 objects; Node CPU median 10 ms (min 10); workerd verify 7 ms wall beyond transfer (3 ms); isomorphic-git indexPack CPU 74 ms; inflated 1 MB, resolved 1 MB, reader peak accounted 206 MB |
| P4 | PASS | 38 ms | text 1 MB: pack 0.90 MB, 388 objects; Node CPU median 38 ms (min 35); workerd verify 16 ms wall beyond transfer (17 ms); isomorphic-git indexPack CPU 291 ms; inflated 5 MB, resolved 5 MB, reader peak accounted 212 MB |
| P4 | INFO | 288 ms | text 10 MB: pack 8.04 MB, 868 objects; Node CPU median 288 ms (min 270); workerd verify 154 ms wall beyond transfer (79 ms); isomorphic-git indexPack CPU 1346 ms; inflated 52 MB, resolved 53 MB, reader peak accounted 266 MB |
| P4 | INFO | 1125 ms | text 50 MB: pack 40.32 MB, 4068 objects; Node CPU median 1125 ms (min 1045); workerd verify 895 ms wall beyond transfer (260 ms); isomorphic-git indexPack CPU 5198 ms; inflated 260 MB, resolved 264 MB, reader peak accounted 509 MB |
| P4 | INFO | 2 ms | binary 100 KB: pack 0.10 MB, 32 objects; Node CPU median 2 ms (min 1); workerd verify 0 ms wall beyond transfer (5 ms); isomorphic-git indexPack CPU 19 ms; inflated 0 MB, resolved 0 MB, reader peak accounted 205 MB |
| P4 | PASS | 5 ms | binary 1 MB: pack 1.06 MB, 138 objects; Node CPU median 5 ms (min 4); workerd verify 2 ms wall beyond transfer (12 ms); isomorphic-git indexPack CPU 35 ms; inflated 1 MB, resolved 1 MB, reader peak accounted 208 MB |
| P4 | INFO | 67 ms | binary 10 MB: pack 10.50 MB, 228 objects; Node CPU median 67 ms (min 47); workerd verify 41 ms wall beyond transfer (60 ms); isomorphic-git indexPack CPU 343 ms; inflated 11 MB, resolved 11 MB, reader peak accounted 226 MB |
| P4 | INFO | 286 ms | binary 50 MB: pack 52.48 MB, 868 objects; Node CPU median 286 ms (min 143); workerd verify 96 ms wall beyond transfer (302 ms); isomorphic-git indexPack CPU 995 ms; inflated 52 MB, resolved 53 MB, reader peak accounted 311 MB |
| P5 | PASS | — | concurrent advances from one head: exactly one winner in 10/10 rounds, loser staleHead |
| P5 | PASS | — | non-descendant head: 409 notDescendant; head unchanged=true |
| P5 | PASS | — | stale expected head: 409 staleHead; head unchanged=true |
| P5 | PASS | — | pack never uploaded: 409 packMissing; head unchanged=true |
| P5 | PASS | — | repeat of the applied advance after a lost response: 200 repeated=true, same head=true |
| P5 | PASS | — | pack from another Generation: 409 wrongGeneration; head unchanged=true; initial upload 200 |
| P6 | PASS | — | A advance 200; B advance 409 staleHead; B merge base 22b3b5b7 = R 22b3b5b7; merge parents [af334522,4825e4c7] = [B af334522, A 4825e4c7]; B advance 200; A fast-forward graph identical=true, files identical=true |
| P7 | PASS | — | re-import of objects the live Store already has: status 0, new pack name "" (empty = no-op); live Store hash unchanged=true |
| P7 | PASS | — | interrupted import killed after 150 ms left 1 staging file(s) [pack_git2_d337b6cadedb69c1]; staging discarded; retry status 0 pack 8039a912; live Store unchanged throughout=true |
| P8 | PASS | — | packs before 3; sweep within grace deleted 0; sweep past grace deleted 28 across all Lineages, this Lineage 3 -> 1 (replaced and never-advanced packs gone), kept head pack=true; Generation delete: prefix lists 0 keys, D1 rows 0 |
| P9 | INFO | — | small Skill (3 KiB text) Head Pack 1404 B; typical Skill (12 KiB text) Head Pack 3043 B; large Skill (40 KiB text + 64 KiB binary) Head Pack 73028 B |
| P9 | INFO | — | 50 edits to a typical Skill: full-closure uploads 633 KiB total, incremental 66.9 KiB total (9x); full Head Pack by history length: 50 edits: 22 KiB, 100 edits: 41 KiB, 200 edits: 79 KiB, 500 edits: 192 KiB, 1000 edits: 382 KiB, 2000 edits: 763 KiB |
| P10 | PASS | — | upload, no session: 401 unauthorized |
| P10 | PASS | — | download, no session: 401 unauthorized |
| P10 | PASS | — | upload with another account's session: 404 notFound; identical to a missing pack=true |
| P10 | PASS | — | download with another account's session: 404 notFound; identical to a missing pack=true |
| P10 | PASS | — | head with another account's session: 404 notFound; identical to a missing pack=true |
| P10 | PASS | — | another account's digest through own Lineage: 404 notFound; identical to a missing pack=true |
| P10 | PASS | — | credential search over 4 R2 keys, D1 rows (457176 chars) and 0 chars of workerd output: none found; URLs carry no credential by construction |

38 lines, 0 failed; the harness exited 0. P4 "Time" is the median Node CPU; for other tests it is the request time where measured. P1's full run, including both Devices, took about 755 ms.

**P3 error codes:** each case is rejected, but two pairs share a code.
- **`packChecksum`:** truncation at the source and one flipped byte both fail
  the pack's own trailer SHA-1. A checksum cannot tell them apart.
- **`inflateLimit`:** with a forged trailer, both fail later, at inflate.
- **`digestMismatch`:** truncation in transit fails first here, because the
  upload's address is the SHA-256 of the full pack.
- **The extra unreachable object** is accepted for a Head Pack, and the reader
  detects and counts it (`unreachableObjects=1`). A Phase 2 Release Pack check
  can reject on that count.

## Method and its limits

- **Device:**
  - `device.py` calls `libskills_workspace_native.so`, which is
    `skills_workspace`'s private ABI over the pinned libgit2 1.9.7.
  - Commits use the Workspace's fixed signature and time, so commit IDs depend
    only on content.
  - System Git is used only:
    - to read Stores (`rev-list --parents`, to compare graphs);
    - to build two adversarial packs with `pack-objects`, the missing-blob pack
      and the extra-object pack, as the brief prescribes;
    - for P9's incremental packs.
- **Worker:**
  - Bundled with esbuild and run in Miniflare's workerd, with
    `nodejs_compat` and compatibility date 2026-07-30.
  - Auth is a stub bearer check, as the brief allows.
- **CPU:**
  - Workers freeze `performance.now()` and `Date.now()` during execution, so a
    Worker cannot time itself.
  - The CPU figure is Node's `process.cpuUsage()` running the identical
    verifier, median of three runs. Node and workerd both run V8, and both use
    native zlib and SHA-1.
  - As a cross-check, the "workerd wall" figure is the local workerd request
    time, minus a request of the same body that skips verification. It agrees
    in magnitude.
  - **Cloudflare's billed CPU time was not measured.** It needs a deployed
    Worker, and its invocation log reports CPU time. This is the one number
    worth confirming on staging before relying on the larger sizes.
- **Pack fixtures (P4):** generated text compresses about 5:1, which is more
  than real prose. The "about 50 MB" text pack therefore came out at 40 MB.
  The random-byte packs do not compress.

## Pack reader and its budget

| | `parsePack` (service repository) | isomorphic-git 1.44.13 |
|---|---|---|
| Licence | ours (private service code) | MIT |
| Input | bytes in memory, explicit byte, object, and delta budgets | a pack file on a filesystem (`indexPack`) |
| Checks | trailer SHA-1, every object's ID, delta bases, depth, size limits; typed error codes | object IDs while indexing |
| CPU, 0.9 MB text pack | 38 ms | 291 ms |
| CPU, 8 MB text pack | 288 ms | 1,346 ms |
| CPU, 40 MB text pack | 1,125 ms | 5,198 ms |
| CPU, 52 MB binary pack | 286 ms | 995 ms |

**Budget by size,** from the P4 lines:

| Head Pack | CPU | Fits Free (10 ms) | Fits Paid (30 s default) | Memory held: pack + inflated objects |
|---|---|---|---|---|
| 0.1 MB | 2–10 ms | borderline | yes | about 1 MB |
| 1 MB | 5–38 ms | no | yes | 2–6 MB |
| 8–10 MB | 67–288 ms | no | yes | 22 MB binary, 61 MB text |
| 40–52 MB | 0.29–1.1 s | no | yes | **105 MB binary (at the limit), about 300 MB text (over)** |

**Memory** is the binding constraint, not CPU. The reader keeps every inflated
object until the walk ends. Its own "peak accounted" statistic includes a
reserve sized from the configured object limit (200,000 objects), so that
figure overstates real use. The table above uses pack plus resolved bytes.

Two ways to stay inside 128 MB, if large Skills matter:
- **(a)** Cap the Head Pack. R16 already lists a pack size bound as a beta
  decision. 16 MB packed and 64 MB inflated keeps the reader under about
  100 MB.
- **(b)** Keep only commit and tree objects in memory, and hash blobs as they
  stream. This lowers memory to roughly the pack size.

Option (a) is enough for Phase 1.

## libgit2 calls

**Export (R11 seam 1):** `skills_workspace_revision_export_pack_create`, in
`native/src/revision_engine.c`, already does this. It pushes each root into a
`git_revwalk`, calls `git_packbuilder_insert_walk`, then
`git_packbuilder_write`. This is the same code that Recovery Bundles use since
T14, with history on. Nothing new is needed.

**Staged import (R11 seam 2):** `skills_workspace_revision_pack_import`:
1. `git_indexer_new` on the staging `objects/pack`, with the live ODB passed in
   for delta bases;
2. `git_indexer_append` and `git_indexer_commit`;
3. `git_odb_open` on staging, then `git_odb_foreach` to check each object;
4. `git_odb_add_disk_alternate` with the live `objects/`, opened read-only;
5. a closure check from the named revisions.

It returns an empty pack name when every object is already live. The
Workspace composition (`prepareRemoteRevisionStore`) then:
1. copies the live Store to a candidate;
2. adds the staged pack to the candidate;
3. verifies the candidate;
4. promotes it.

`device.py import` does the same. The recovery-pack code was the starting
point; seam 2 already reuses its verification.

**Incremental packs (P9 only):** these need the previous head hidden
(`git_revwalk_hide`). The native ABI does not expose that. The prototype used
`git pack-objects --revs` for the measurement.

## Cost sketch

Prices are from Cloudflare's documentation, read on 2026-11-27 (sources
below).

**Assumptions:**
- 20 synced Skills per user, and 4 Uploads per user per day. Each Upload is one
  pack PUT and one Head Advance; the other Device then makes one head read and
  one pack download.
- A Feed Check every 2 minutes for 8 hours a day: 240 per user per day.
- The average Head Pack is 50 KB, which is a typical Skill after about 120
  edits. One live pack per Skill, plus 10% for grace.
- CPU: 10 ms per pack upload, 3 ms per advance, 2 ms per other request.
- D1:
  - about 4 rows written per Upload;
  - about 100 bytes per commit row, with 120 commits per Skill;
  - 10 rows read per Feed Check;
  - 120 rows read per ancestry query.
- Workers Paid plan, $5 a month. 30-day months.

| Active users | Requests per month | Workers | R2 | D1 | Total per month |
|---|---|---|---|---|---|
| 1,000 | 7.7 M | $0 (included) | $0 (free tier) | $0 | **about $5** |
| 10,000 | 77 M | $20 requests + $3 CPU | $4.50 (Class A) | $0 | **about $32** |
| 100,000 | 768 M | $227 requests + $32 CPU | $50 Class A + $2 storage and Class B | $14 storage | **about $331** |

**What drives the cost:**
- **Feed Check requests,** about 94% of all requests. Feed Check cadence is the
  lever, not pack size.
- **Pack storage** stays small: about 110 GB at 100,000 users.

**Scaling limits that matter more than price:**
- **D1 database size:** at 100,000 users the commit graph reaches about 24 GB,
  above D1's 10 GB maximum per database. The service must shard D1, for example
  by account.
- **D1 throughput:** each D1 database runs one query at a time. 100,000 users
  give about 280 Feed Checks a second on average, near a single database's
  ceiling at about 1 ms per query. That is a second reason to shard.

## Blockers

**None.** Nothing measured forces the R15 fallback (sending raw commit objects)
or a return to Git hosting.

Risks to carry into M4:
- **Workers Free cannot verify packs:** 10 ms CPU covers only about 0.1 MB. The
  service must run on Workers Paid. It was planned to.
- **Memory, not CPU,** bounds the largest pack. This needs a pack size bound.
- **The Worker re-inserts the whole commit graph** on every Upload, using
  `INSERT OR IGNORE`. Whether D1 bills ignored inserts as rows written is
  **UNVERIFIED**. Inserting only unknown commits avoids the question.

## Decisions for the maintainer

1. **R16 rule:** P2 and P4 pass, so build R15 as written. Recommended.
2. **Head Pack size bound** for Phase 1. Suggested: 16 MB packed and 64 MB
   inflated, rejected at upload with a typed error. The App then shows an
   Attention Reason or a size message.
3. **D1 layout:** shard the commit graph and the Lineages by account from the
   start, or start with one database and plan the split. With 100,000
   databases included in Workers Paid, per-account sharding is cheap.
4. **Optional:** incremental packs. They cut upload bytes by about 9 times at
   50 edits. They would need `git_revwalk_hide` in the native ABI, and they are
   R15's stated non-goal (no pack chains). Not recommended for Phase 1.

## Sources (read 2026-11-27)

- **Workers limits:**
  `https://developers.cloudflare.com/workers/platform/limits/` (updated
  2026-11-25).
  - CPU per HTTP request: 10 ms on Free; on Paid, 30 s by default, up to 5 min.
  - Memory: 128 MB per isolate.
  - Request body: 100 MB on the Free and Pro zone plans, 200 MB on Business.
- **Workers pricing:**
  `https://developers.cloudflare.com/workers/platform/pricing/` (updated
  2026-11-18).
  - $5 a month minimum.
  - 10 M requests included, then $0.30 per million.
  - 30 M CPU ms included, then $0.02 per million.
  - The D1 prices on that page match the D1 page below.
- **R2 pricing:** `https://developers.cloudflare.com/r2/pricing/` (updated
  2026-10-30).
  - Standard storage: $0.015 per GB-month.
  - Class A operations: $4.50 per million. Class B: $0.36 per million.
  - Free tier: 10 GB, 1 M Class A, and 10 M Class B a month.
  - Egress is free and deletes are free.
- **R2 data location:**
  `https://developers.cloudflare.com/r2/reference/data-location/` (updated
  2026-08-19). Jurisdictions are `eu`, `fedramp` (Enterprise), and `us`. A
  bucket's jurisdiction cannot be changed after creation.
- **D1 pricing:** `https://developers.cloudflare.com/d1/platform/pricing/`
  (updated 2026-10-30).
  - Rows read: 25 B included, then $0.001 per million.
  - Rows written: 50 M included, then $1.00 per million.
  - Storage: 5 GB included, then $0.75 per GB-month.
- **D1 limits:** `https://developers.cloudflare.com/d1/platform/limits/`
  (updated 2026-11-20).
  - 10 GB per database on Paid; 100 bound parameters per query.
  - 1,000 queries per invocation on Paid; a batch counts as one query.
  - A database is single-threaded.
- **`DecompressionStream`:**
  `https://developers.cloudflare.com/workers/runtime-apis/web-standards/`
  (updated 2026-04-23). It supports `deflate`, `deflate-raw`, and `gzip`. The
  prototype uses `node:zlib` through `nodejs_compat` instead. The same page
  says `Date.now()` and `performance.now()` do not advance during execution.
