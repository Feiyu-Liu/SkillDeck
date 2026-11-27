# ExecPlan: T21 Service: Head Packs, Head Advance, and Generation change

Milestone M4, service side, part 2 of 2. **Runs in the private service
repository,** after T20. The maintainer copies this card into that repository;
Codex keeps the maintained sections of that copy. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

On dev, a Device can do the whole content cycle:
- upload a verified Head Pack;
- move a Lineage Head with Head Advance;
- change Generation for Source Replacement;
- download the head's pack.

All of it is exactly as contract v0.1 specifies, within the 16 MB packed and
64 MB inflated bound.

### Context

- **Read first:** contract v0.1, sections Head Packs, Head Advance, and
  Generation change; T20's code; and the prototype on branch
  `spike/revision-pack-prototype`, `spikes/revision-pack/`.
- **The prototype already shows** that the design works:
  - `verify.ts` reuses `src/providers/pack.ts` `parsePack` and adds a closure
    walk;
  - `worker.ts` has the CAS update and the recursive ancestry query.

  Start from it, but it is not production code: no real auth, an
  unauthenticated sweep, and it re-inserts the whole Commit Graph on every
  upload.
- **Measured** (report on the SkillDeck branch,
  `revision-pack-prototype-results-2026-11-27.md`):
  - a 0.9 MB pack verifies in about 40 ms of CPU;
  - memory, not CPU, bounds the largest pack. The reader holds the pack plus
    every inflated object.
- **Decided 2026-11-27:**
  - R15 as written;
  - packs above 16 MiB packed or 64 MiB inflated get `413 packTooLarge`;
  - D1 is sharded by account, from T20;
  - an end (Synced Removal or Stop Syncing) wins over a concurrent advance.

### Contract

- **Upload:** `PUT /v0/lineages/{id}/generations/{g}/packs/{sha256}`, as
  specified.
  - Check `Content-Length` before reading the body.
  - Configure `parsePack` so that its own inflated-bytes limit enforces the
    64 MiB bound.
  - Accept uploads to the current or the next Generation.
  - Insert only commits that the Generation's Commit Graph does not hold yet.
- **Download:** `GET`, on the same path. Stream it from R2; do not buffer it.
- **Head Advance:** `POST /v0/lineages/{id}/head`, with the repeat check first,
  then rules 1–5 in order, and every error with its extra fields. It fills
  `head.device` from the session's Device description, which T20 stores.
- **Generation change:** `POST /v0/lineages/{id}/generations`, atomic, with its
  repeat rule.
- **Retention:**
  - unreferenced packs are deleted after 24 hours;
  - an ended or replaced Generation's packs and Commit Graph go after 7 days;
  - listing the prefix afterwards returns no keys.

  This runs in T20's scheduled sweep, with configurable times.
- **R2 keys:** `lineages/<lineage>/<generation>/<sha256>.pack` (R15), in the
  private bucket. Never shared across accounts.

### Acceptance

Tests in the Workers runtime against local D1 and R2.

- **Upload:**
  - a valid pack is accepted;
  - repeating it answers the same 200;
  - each `packRejected` reason has a test: digest, checksum, format, missing
    root, and missing object;
  - `packTooLarge` is tested for `packed`, via `Content-Length`, and for
    `inflated`, via a small pack that inflates past the bound;
  - a pack for a Generation that is neither current nor next is rejected;
  - an ended Lineage answers 410.
- **Head Advance:** one test per rule, in the contract's order. Each rejection
  leaves the Lineage unchanged.
  - Two concurrent advances from one head: exactly one wins, in at least 10
    rounds.
  - A repeated advance after a lost response returns the same state.
  - The first advance from `null` works.
  - `head.device` names the advancing session's Device.
- **Generation change:**
  - it is atomic: no read observes the new Generation without its head;
  - a repeat answers 200;
  - a wrong `expectedGeneration` answers `wrongGeneration` with `lineage`;
  - an old Generation's packs are deleted after its grace.
- **Ending versus advancing:** an end that lands between two advances makes the
  later advance answer 410 `lineageEnded`.
- **Feed:** every advance, Generation change, and end moves exactly one feed
  entry and increases `version`.
- **End to end:** the prototype harness's P1, P5, P6, and P8 scenarios pass
  against the real endpoints, with real sessions instead of the stub. Drive the
  Device CLI `branch-doc/prototype/revision-pack/device.py` from the SkillDeck
  branch, as the prototype harness does.
- **Measurement:** record CPU and wall time to verify a 1 MB and a 16 MB pack
  in workerd. Use the prototype's method; there is no threshold.
- **Gates:** the repository's format, typecheck, tests, and build, each with its
  own exit code; all T17 and T20 tests unchanged.

### Scope fence

- **Out of scope:**
  - metadata and tags (v0.2, M6);
  - incremental packs;
  - streaming verification that keeps blobs out of memory;
  - deploying;
  - changing the contract.
- **Expected size:** about 12–20 files, 1,500–2,500 lines including tests.

### Stop and ask if

- Enforcing the 64 MiB inflated bound needs a change to `parsePack` beyond its
  existing limits.
- A 16 MiB pack does not verify within the memory limit in workerd.
- Atomic Generation change cannot be done in one D1 transaction or batch.

## Maintained by Codex

Kept in the service repository's copy of this card.
