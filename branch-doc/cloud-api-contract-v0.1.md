# SkillDeck Cloud API contract v0.1: Personal Sync data API

Status: draft, 2026-11-27. Milestone M4. Extends `cloud-api-contract-v0.md`:
every convention there still applies here, sign-in is unchanged, and so is
HTTP 429. The private service repository implements this contract; the
`skills_cloud` client implements the client side.

Sources of truth, in the accepted ADR-0105 revision
(`0105-revision-2026-11-23-proposal.md`):
- R3: Head Advance and Reconciliation;
- R4: what applies without asking;
- R6: lifecycle;
- R8: the feed;
- R10: Attention Reasons;
- R15: Revision Packs.

Decisions of 2026-11-27, from the Revision Pack prototype:
- R15 is built as written;
- a Head Pack is bounded at 16 MB packed and 64 MB inflated;
- D1 is sharded by account. The API never shows a shard.

Vocabulary follows `packages/skills_cloud/CONTEXT.md`.

v0.1 covers content sync:
- the Cloud Library;
- Cloud Lineages and their Generations;
- Head Packs;
- Head Advance;
- Synced Removal and Stop Syncing;
- the Account Change Feed.

Skill Extra Data, Skill Tag Assignments, the Synced Tag Vocabulary, and Field
Versions come in v0.2, with M6. Nothing here may assume their shape, except
that the feed already allows more entity kinds.

## Conventions added in v0.1

- **Paths:** every data endpoint is under `/v0/` and needs the Cloud Session
  (`Authorization: Bearer`).
- **Bodies:** JSON, `application/json`, except pack bodies, which are raw
  `application/x-git-packed-objects`. The client ignores response fields it
  does not know; the service rejects request fields it does not know with
  `invalidRequest`.
- **Identifiers:**
  - `lineageId` is server-minted and opaque, at most 64 characters;
  - a revision is a 40-character lowercase commit ID (R16);
  - a pack is named by the 64-character lowercase hex SHA-256 of its bytes;
  - `generation` is an integer starting at 1.
- **Errors:** HTTP 4xx with `{"error": "<code>"}` and, where listed, extra
  fields. Codes are stable. The client never shows or logs server text.
- **Not found:** an unknown Lineage, another account's Lineage, and a pack the
  caller cannot read all answer the same HTTP 404 `notFound`.
- **Account conditions** (R10), on any data endpoint:
  - HTTP 401: sign-in required, as in v0;
  - HTTP 403 `storageLimitReached`: on calls that would store more. The quota
    values are a beta decision.
- **Retry:** a lost response is resolved by reading state again (R3). Every
  write below is safe to repeat, as each section says. There are no client
  receipts.

## Objects

### Lineage

```json
{
  "lineageId": "…",
  "version": 7,
  "state": "live",
  "generation": 2,
  "source": { "…": "opaque" },
  "head": {
    "effective": "<commit>",
    "upstream": "<commit>",
    "pack": "<sha256>",
    "declaredName": "my-skill",
    "device": { "name": "Studio Mac", "platform": "macos" }
  },
  "updatedAt": "2026-11-27T10:00:00.000Z"
}
```

- **`version`:** increases by at least 1 on every committed change to the
  Lineage. It is the version the feed reports.
- **`state`:**
  - `live`;
  - `removed`: a Synced Removal tombstone;
  - `stopped`: Stop Syncing.

  `head` is `null` unless `state` is `live`.
- **`source`:** the Portable Source of the current Generation, as a JSON object
  of at most 4 KB.
  - `skills_cloud` defines and versions its encoding. The service stores it and
    returns it unchanged, and checks only its size and that it is an object.
  - It never holds an absolute path; the client guarantees this.
- **`head.upstream`:** `null` for a Skill with no Upstream commit, for example
  an Adopted Snapshot on its Origin Device.
- **`head.declaredName`:** at most 256 bytes of UTF-8. It may change within a
  Generation.
- **`head.device`:** the Device whose session made this head, named as at its
  sign-in (v0, `device_name` and `device_platform`). The client uses it to
  attribute an Update Candidate Session to the other Device (R4). This needs the
  service to keep the Device description with each session.
- **A Lineage that is `live` with `head: null`** exists only between its
  creation and its first Head Advance.

## Cloud Library

### List the Cloud Library

`GET /v0/library?cursor=<opaque>&limit=<1..500>`

```json
{ "lineages": [ "Lineage…" ], "next": "<opaque>|null", "feedCursor": "<opaque>" }
```

- Only `live` Lineages are listed. The order is stable.
- **`feedCursor`:** a feed position taken before the listing started. A Device
  that lists the whole library and then reads the feed from `feedCursor` misses
  no change.
- `feedCursor` is the same on every page of one listing.
- **New-Device bootstrap** (R6) and **reset** both use this listing.

### Read one Lineage

`GET /v0/lineages/{lineageId}` returns the Lineage in any `state` while its
tombstone is retained (90 days, R6). After that, it answers 404 `notFound`.

### Create a Lineage

`POST /v0/lineages`

```json
{ "clientKey": "<uuid>", "source": { "…": "opaque" } }
```

- Answers 201 with a `live` Lineage, at `generation` 1, with `head: null`.
- **`clientKey`:** chosen by the client and kept with its pending link, so the
  request is safe to repeat. The same account and the same `clientKey` within
  30 days return the same Lineage, with 200, even if its state has changed
  since.
- The client then uploads a Head Pack and advances from `expected: null`.
- A created Lineage that is never advanced is deleted after 24 hours, with its
  packs. It never appears in the library or the feed.
- Failures: `invalidRequest` (400); `storageLimitReached` (403).

## Head Packs

### Upload a Head Pack

`PUT /v0/lineages/{lineageId}/generations/{generation}/packs/{sha256}`

Headers:
- `Content-Type: application/x-git-packed-objects`;
- `Content-Length` (required);
- `SkillDeck-Pack-Roots: <effective>[,<upstream>]`.

The body is the pack written by Workspace seam 1, holding the complete closure
of the named roots.

- **`generation`:** must be the Lineage's current Generation, or the next one
  (current + 1) when uploading for a Generation change.
- **The service:**
  - refuses a `Content-Length` above 16 MiB before reading the body;
  - checks that the body's SHA-256 equals `{sha256}`;
  - runs Pack Verification: every object ID is recomputed, and the closure of
    the roots is complete;
  - stores the pack;
  - adds its commits to the Commit Graph of that Generation.
- **Success:** 200 `{"sha256": "…", "commits": <n>}`. Uploading a stored pack
  again answers the same 200.

| HTTP | `error` | Meaning | Client action |
|---|---|---|---|
| 400 | `invalidRequest` | headers or roots malformed | protocol failure |
| 404 | `notFound` | Lineage unknown or not the caller's | reconcile the Lineage |
| 409 | `wrongGeneration` | `generation` is neither current nor next; body has `"generation": <current>` | reconcile the Lineage |
| 410 | `lineageEnded` | the Lineage is `removed` or `stopped` | reconcile the Lineage |
| 413 | `packTooLarge` | over 16 MiB packed, or over 64 MiB inflated; body has `"limit": "packed"` or `"inflated"` | Attention Reason, see Open points |
| 422 | `packRejected` | body has `"reason"`: `digestMismatch`, `packChecksum`, `packFormat`, `missingRoot`, or `missingObject` | an export defect: do not retry this pack |
| 403 | `storageLimitReached` | account quota | account condition |

`reason` exists for diagnostics, and the client may record it. Phase 1 accepts
objects in the pack that the roots do not reach.

### Download a Head Pack

`GET /v0/lineages/{lineageId}/generations/{generation}/packs/{sha256}`

- 200, with the raw pack, `Content-Length`, and `Content-Type:
  application/x-git-packed-objects`.
- The client checks the SHA-256 against `{sha256}`, then imports through
  Workspace seam 2.
- **Readable packs:** the current head's pack, and for 24 hours any pack that a
  head of that Generation referenced. Anything else is 404 `notFound`.
- Downloads happen only for Lineages whose feed entry changed, or during
  bootstrap and reset (R8). Pack storage is never polled.

### Retention (service)

- **Unreferenced packs:** a pack that no head references is deleted 24 hours
  after upload, or 24 hours after a head stopped referencing it.
- **Ended Generations:** a Generation's packs and Commit Graph are deleted 7
  days after it stops being current, through a Generation change, Synced
  Removal, or Stop Syncing.
- **After deletion,** listing the Generation's storage prefix returns no keys
  (ADR-0089).

## Head Advance

`POST /v0/lineages/{lineageId}/head`

```json
{
  "generation": 2,
  "expected": { "effective": "<commit>", "upstream": "<commit>|null" },
  "next": {
    "effective": "<commit>",
    "upstream": "<commit>|null",
    "pack": "<sha256>",
    "declaredName": "my-skill"
  }
}
```

`expected` is `null` only for the first head of a Generation.

**Repeating an advance** is checked first: if the current head already equals
`next` (all four fields), the service answers 200 with the Lineage, whatever
`expected` says. This settles a lost response.

**Otherwise the service accepts the advance only when all of these hold,**
checked in this order. The first rule that fails gives the error. Rules 4 and 5
apply only when `expected` is not `null`.

1. The Lineage is `live`, and `generation` is current.
2. The current head equals `expected`. `effective` and `upstream` are compared;
   `pack` and `declaredName` are not.
3. `next.pack` is a verified pack of this Generation whose roots include
   `next.effective` and, when it is not `null`, `next.upstream`.
4. **Effective descends:** `next.effective` equals `expected.effective` or
   descends from it in the Commit Graph.
5. **Upstream rule (R3):**
   - if `expected.upstream` is `null`, `next.upstream` is `null`;
   - otherwise `next.upstream` equals `expected.upstream` or descends from it.

**Then,** in one transaction, it:
- writes the head;
- increases `version`;
- records `head.device` from the caller's session;
- moves the Lineage's feed entry.

**Success:** 200 with the Lineage.

| HTTP | `error` | Extra fields | Client action |
|---|---|---|---|
| 409 | `staleHead` | `"lineage": Lineage` | reconcile against the returned head |
| 409 | `wrongGeneration` | `"lineage": Lineage` | reconcile, apply the Generation change |
| 409 | `packMissing` | | upload the pack, then advance again |
| 409 | `packLacksHead` | | an export defect |
| 409 | `notDescendant` | | a client defect: Reconciliation should have merged |
| 410 | `lineageEnded` | `"lineage": Lineage` | apply the Removal or Stop Syncing |
| 404 | `notFound` | | reconcile the Lineage |

## Generation change (Source Replacement)

`POST /v0/lineages/{lineageId}/generations`

```json
{
  "expectedGeneration": 2,
  "source": { "…": "opaque" },
  "next": {
    "effective": "<commit>",
    "upstream": "<commit>|null",
    "pack": "<sha256>",
    "declaredName": "…"
  }
}
```

- **Before calling:** the client uploads the new Generation's pack to
  `generations/{expectedGeneration + 1}`.
- **Atomic:** the service checks the pack as in Head Advance rule 3, within the
  new Generation. Then, in one transaction, it:
  - starts Generation `expectedGeneration + 1` with `source` and `next` as its
    first head;
  - increases `version`;
  - moves the feed entry.

  No Device ever sees a new Generation without a head.
- **Success:** 200 with the Lineage.
- **Repeating it:** if the current Generation is already
  `expectedGeneration + 1` with the same `source` and head, the service answers
  200.
- **Failures:**
  - `wrongGeneration` (409, with `lineage`) when `expectedGeneration` is not
    current;
  - `packMissing`, `packLacksHead`, `lineageEnded`, and `notFound`, as above.
- There is no ancestry rule: a new Generation's history is unrelated.

## Ending a Lineage

`POST /v0/lineages/{lineageId}/removal` (Synced Removal), and
`POST /v0/lineages/{lineageId}/stop` (Stop Syncing), both with body `{}`.

- **Unconditional:** an end wins over a concurrent Head Advance, as a tag
  delete wins over a concurrent assignment (R5).
- The service sets `state`, sets `head` to `null`, increases `version`, and
  moves the feed entry. Then retention starts for the current Generation.
- **Success:** 200 with the Lineage.
- **Repeating it:** ending a Lineage again in the same way answers 200.
  Ending it the other way answers 410 `lineageEnded` with `lineage`.
- **Other Devices** (R4, R6):
  - `removed`: they perform Removal automatically, unless a Dirty Draft or an
    Update Candidate Session exists. That case is the Attention Reason
    "Removed on another Device while a Draft exists here";
  - `stopped`: they keep their copy as Device Only.
- **Tombstones:** retained for 90 days. During that time the Lineage stays
  readable and its feed entry stays.

## Account Change Feed

`GET /v0/feed?after=<cursor>&limit=<1..1000>`

```json
{
  "entries": [
    { "kind": "lineage", "id": "<lineageId>", "version": 7 }
  ],
  "cursor": "<opaque>",
  "more": false
}
```

- **What it holds:** at most one entry per entity, for its latest change,
  ordered by when that change committed. `version` is the entity's version at
  that change.
- **`after`:**
  - omitted means "from the beginning";
  - otherwise use the `cursor` of the previous response, or a library listing's
    `feedCursor`.
- **Empty results:** with nothing new, the service answers `entries: []` and
  `cursor` equal to `after`. This is the cheap Feed Check (R8).
- **`more: true`:** call again at once with the new cursor.
- **Unknown kinds:** the client skips any `kind` it does not know. v0.2 adds
  kinds for metadata and tags.
- **What a client does with an entry:** it reads the entity, here
  `GET /v0/lineages/{id}`, and reconciles. It never applies the entry itself.
  An entry whose `version` is not newer than the version the Device last
  reconciled needs nothing.
- **Interval:** the service may send `Retry-After` on a 200 to lengthen the
  next periodic Feed Check, and on 429 or 503. T04's scheduler honors both.
- **Expired cursor:** HTTP 410 `cursorExpired`, when the cursor is older than
  the oldest change the feed still holds, for example after tombstones expired.
  The Device then resets: it lists the library, and treats each linked Skill
  missing from it as the Attention Reason "Missing from the Cloud Library after
  a reset" (R6, R10).

## Client flow (informative)

This section is for the M4 client card. It does not bind the service.

- **Reconciliation** of one linked Skill with local Effective L and Lineage
  head R:
  - **`state` is not `live`:** apply the Removal, or keep the Skill as Device
    Only.
  - **The Generation changed:** download the new head's pack, then apply it as
    the Generation change (R4).
  - **L = R:** nothing.
  - **R is unknown locally:** download R's pack and apply through
    `applyRemoteState`. The Workspace answers `fastForwarded`, `merged`,
    `conflicted`, `draftResolutionRequired`, or `noChange`.
  - **After a `merged`, or with L ahead of R:**
    1. export a Head Pack for L;
    2. check that it is at most 16 MiB;
    3. upload it;
    4. advance, expecting R.

    A `staleHead` answer starts Reconciliation again with the returned head.
- **New Lineage:** create the Lineage, upload a Head Pack, then advance from
  `null`.
- **New Device:** list the library, then install each Lineage that is not
  excluded. Then read the feed from `feedCursor`.
- **What the client keeps:**
  - per Device: the feed cursor;
  - per linked Skill: the Lineage mapping, the last reconciled `version`, and,
    for a Lineage being created, its `clientKey`.

  Nothing else is queued.

## Service obligations beyond the endpoints

- Shard the Commit Graph, Lineages, and feed by account. One account's
  requests never need two shards.
- Insert only commits that the Generation's Commit Graph does not already
  hold.
- Keep each session's Device description from sign-in, for `head.device`. This
  is a follow-up to T17.
- Never log session tokens, `source` contents, declared names, or Device names.

## Open points (recommendations, for the maintainer)

1. **A Head Pack over the bound** (`packTooLarge`) needs an Attention Reason
   that R10 does not list yet: "Too large to sync".
   - Recommended actions: keep it here as Device Only; Stop Syncing.
   - R10's rule is that every status is resolvable, so this belongs in R10.
2. **Ending wins over a concurrent advance:** recommended as above. The other
   Device's newest revision survives only on that Device, as Device Only or
   behind a Draft.
3. **`clientKey` retention:** 30 days, as above.
