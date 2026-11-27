# SkillDeck Cloud API contract v0.2: Personal Sync metadata

Status: Draft, awaiting the maintainer. Milestone M6. The wire shapes and
recommendations below are proposed for T33 and T34. The binding decisions come
from R5 and R11, the Cloud context, and the M5 apply contract.

- [Accepted ADR-0105 revision](0105-revision-2026-11-23-proposal.md)
- [Cloud context](../packages/skills_cloud/CONTEXT.md)
- [M5 apply contract](m5-sync-apply-contract.md)
- [v0 conventions](cloud-api-contract-v0.md) and [v0.1 data API](cloud-api-contract-v0.1.md)

## Conventions and Field Versions

The v0 and v0.1 conventions apply. All endpoints below use JSON and an
account-scoped Cloud Session. Service writes, their derived changes, and feed
updates commit in one transaction in the account's shard. Note text, tag
names, and Device descriptions are private account data. Exclude them from
logs and diagnostic events, including error payloads captured as diagnostics.

A Field Version is a non-negative JSON integer within JavaScript's safe
integer range. The service increases the version of each changed field.
Expectations are scoped to the resource and field named by the endpoint.
Version `0` denotes an untouched Favorite, Note or assignment. A write
supplies `expectedVersion` and changes state only when the expectation matches.
The initial tag write expects absence with `expectedVersion: null`.

A matching submitted value may return the current state without mutation even
if the expectation is stale. This settles a lost response where the value
still matches. A no-op advances neither a Field Version nor the feed.
Favorites, assignments, tag names and tag colors converge in server acceptance
order. On a stale version the client reads the current state and sends a new
compare-and-set only if local state still calls for the write.

The following errors are shared. The endpoint tables show which apply and
define additional errors. Unknown request fields are `invalidRequest`.

| HTTP | `error` | Meaning |
| --- | --- | --- |
| 400 | `invalidRequest` | Malformed path, query or body, or invalid field value |
| 401 | Per v0 | Session is missing, invalid, expired or revoked. The client acts on status |
| 403 | `storageLimitReached` | The account cannot store more data |
| 404 | `notFound` | The resource is unknown or outside this account. For metadata this also covers a Lineage with no first Head Advance |
| 409 | `staleFieldVersion` | The expectation is stale. The endpoint specifies the current state in the error body |
| 409 | `noteConflict` | A Note Conflict is open. Body includes `"note"` with the current Note object and its conflict |
| 409 | `noNoteConflict` | There is no conflict to resolve. Body includes `"note"` with the current Note object |
| 410 | `lineageEnded` | Metadata Lineage is removed or stopped. Body includes `"lineage": Lineage` per v0.1 |
| 410 | `tagDeleted` | The account's tag has ended through deletion |
| 410 | `tagMerged` | The account's tag was merged. Body includes `"replacementTagId": "<live tagId>"` |
| 413 | `metadataTooLarge` | Body includes `"field": "note"` or `"field": "name"` |
| 429 | `rate_limited` | v0 rate limiting and optional `Retry-After` |

HTTP 401 and 429 apply to every table. HTTP 403 applies to state changes
requiring added storage. Validate the request, account and resource lifecycle
before comparing field versions or treating a repeat as a no-op.

## Objects

`LineageMetadata` is independent of a Lineage's content version.

```json
{
  "lineageId": "<lineageId>",
  "version": 12,
  "favorite": { "value": true, "version": 2 },
  "note": { "value": "My note", "version": 4, "conflict": null },
  "assignments": [{ "tagId": "<tagId>", "version": 3 }]
}
```

- Metadata starts at `version: 0` with a false Favorite, a null Note, and no
  assignments. Its version increases when a field or conflict changes.
- `assignments` is the complete set of currently assigned server tag IDs,
  in stable ID order. Each assignment has its own version.
  `Assignment` is `{ "tagId": "<tagId>", "assigned": true, "version": 3 }`.
  An unset membership reads as `assigned: false`. Its version is retained
  after unassignment while both the Lineage and the tag are live so a stale
  writer cannot revive a former membership using version `0`.
- `note.conflict` is null or the `NoteConflict` below. The Note keeps its
  current committed value while the conflict is open. Each candidate's
  `device` is the v0.1 `head.device` description captured from its editing
  session. A null candidate `text` represents clearing the Note.

```json
{
  "baseVersion": 2,
  "accepted": { "text": "Text A", "device": { "name": "Studio Mac", "platform": "macos" } },
  "incoming": { "text": "Text B", "device": { "name": "Laptop", "platform": "macos" } }
}
```

`Tag` is a live vocabulary entry.

```json
{
  "tagId": "<tagId>",
  "name": "Research",
  "normalizedName": "RESEARCH",
  "color": "#AABBCC",
  "version": 4,
  "nameVersion": 2,
  "colorVersion": 3
}
```

The service mints opaque `tagId` values of at most 64 characters and never
reuses an ID. `nameVersion` and `colorVersion` are independent Field
Versions. The tag `version` guards deletion against changes to either
field. The three versions start at 1. `color` accepts six case-insensitive
hex digits after `#`, or null, and the service returns uppercase hex.
`TagVocabulary` has shape `{ "version": 5, "tags": [Tag, ...] }` with all
live tags in stable ID order. The vocabulary version starts at 0 and
increases on each committed vocabulary change.

## Normalization and proposed limits

For a tag display name, apply Dart `String.trim()`, then NFC. Reject an empty
result or U+0000. The normalized key is NFKC of the display name, followed by
Dart `String.toUpperCase()`. The service computes both values and compares
keys by exact equality. Create, rename, lookup and Workspace vocabulary
apply share one local helper. T33 should qualify its implementation against
the supported Dart runtime for case mappings and whitespace such as
U+0085, as well as NFC accents and compatibility forms.
[Workspace normalization source](../packages/skills_workspace/lib/src/application/library/library_mutation_planner.dart#L463-L488)

For a non-null Note, use the Workspace's Dart `String.trim()` behavior and
reject an empty result. Preserve internal whitespace and case. Use JSON
`null` to clear the Note. Compare and measure the normalized value.
[Workspace Note normalization source](../packages/skills_workspace/lib/src/application/library/library_mutation_planner.dart#L469-L475)

| Limit | Proposal | Error |
| --- | --- | --- |
| Note text, including each conflict candidate and resolution | 4 KiB UTF-8 per text | 413 `metadataTooLarge` with `field: "note"` |
| Tag name | 64 Unicode scalar values in the display name | 413 `metadataTooLarge` with `field: "name"` |
| Vocabulary | 256 live tags per account. Resolving a duplicate name is allowed at this limit | 403 `storageLimitReached` |

Writes rejected by a limit change no state.

## Skill metadata endpoints

Paths in the table are relative to `/v0/lineages/{lineageId}/metadata`.
Metadata is available after the first Head Advance and follows the Lineage
across Generation changes. Reads have no request body.

| Method and path | Request | Success | Errors in addition to shared account conditions |
| --- | --- | --- | --- |
| `GET` at the base path | — | 200 `LineageMetadata` | 400 `invalidRequest`, 404 `notFound`, 410 `lineageEnded` |
| `GET /favorite` | — | 200 the `favorite` object | Same as metadata read |
| `PUT /favorite` | `{ "expectedVersion": 2, "value": false }` | 200 the current `favorite` object | Same as metadata read, 409 `staleFieldVersion` with `favorite` |
| `GET /assignments/{tagId}` | — | 200 `Assignment` | Same as metadata read, 410 `tagDeleted` or `tagMerged` |
| `PUT /assignments/{tagId}` | `{ "expectedVersion": 3, "assigned": false }` | 200 current `Assignment` | Same as assignment read, 409 `staleFieldVersion` with `assignment: Assignment` |
| `GET /note` | — | 200 the `note` object | Same as metadata read |
| `PUT /note` | `{ "expectedVersion": 4, "value": "Text" }` with optional `baseVersion` as described below | 200 the current `note` object, including any conflict opened | Same as metadata read, 409 `staleFieldVersion` with `note`, 409 `noteConflict` with `note`, 413 `metadataTooLarge` |
| `POST /note/resolve` | `{ "expectedVersion": 5, "value": "Chosen or combined text" }` | 200 the current `note` object | Same as metadata read, 409 `staleFieldVersion` or `noNoteConflict` with `note`, 413 `metadataTooLarge` |

Setting an assignment requires a live tag. When a tag is deleted, receiving
`tagDeleted` or `notFound` settles a pending assignment for its ID. When an
assignment was already present on a merged tag at commit time, the merge
transfers it. A retry on that ended tag returns `tagMerged`. The client
refreshes vocabulary and reconciles actual local assignments before writing
against the surviving ID.

### Note writes and resolution

The stale-base algorithm and retention described here are an unresolved
proposal. The open questions compare this with a smaller design.

1. A regular `PUT /note` with the current Field Version and a different
   value sets the Note and records the accepted edit's input Field Version,
   value, and Device. Two submissions for the same base and same normalized
   text settle without a conflict.
2. When a regular PUT has an older expectation, compare the submitted text
   to the edit accepted from that base, when one exists. A repeat of the
   accepted text or a previously considered text is a no-op. A different
   text returns 409 `staleFieldVersion` with `"baseVersion": <that base>`,
   even if a later edit happened to set the same text as the incoming one.
   If the old expectation has no accepted edit, omit `baseVersion` and
   return the current Note, with 200 for a current-value match or 409
   `staleFieldVersion` otherwise.
   The client may submit its still pending text again with that `baseVersion`
   and `expectedVersion` set to the returned current Note version.
3. A PUT with `baseVersion` compares and sets against the current Note
   version. It requires a previously accepted edit at `baseVersion` and a
   different incoming text. A `baseVersion` that does not identify an
   accepted edit is 400 `invalidRequest`. Another stale expectation returns
   409 `staleFieldVersion` with the same base and the latest `note`. An
   already considered text returns the current Note as a no-op. On success
   the service preserves both edits and their Device descriptions, opens
   the conflict, and advances the Note Field Version. This also covers a
   delayed edit after several intervening Note changes. The current Note
   stays visible in `note.value` even if it differs from both candidates.
4. With a conflict open, ordinary writes of either candidate can return the
   current conflict as a no-op. Any different write returns 409
   `noteConflict` with the current `note`. A third Device keeps the third
   text in its Workspace and rechecks it against its original base after the
   open conflict resolves.
5. Resolution compares and sets against the open conflict's current Note
   version, uses the submitted value, clears the conflict, and advances the
   version. The value can be either candidate, a combined text, or null if
   the person chooses to clear the Note. Record the resolution and resolving
   Device as the accepted edit from the last settled version before the
   conflict opened, so a Device that missed the conflict can still compare
   its local edit from that version. A stale resolution returns
   `staleFieldVersion`, except when the conflict is already closed and the
   submitted value matches current state. With a current expectation but no
   open conflict, a different value returns 409 `noNoteConflict`. The client
   reads the latest state after a lost resolution response and submits a
   different resolution only after a new user choice.

**Proposed retention.** Preserve the accepted edit for each valid base while
the Lineage is live. Once resolved, keep only enough information about the
incoming candidate to recognize it if it is submitted again from that base.
A previously considered text returns the current Note state without mutation,
so a lost response does not reopen a resolved conflict. A different third
candidate can open another conflict on the same base. Persisted information
describes Note state and its edits. Reconciliation needs no client receipt or
intent queue.

## Vocabulary endpoints

Reads have no request body. All paths are absolute.

| Method and path | Request | Success | Errors in addition to shared account conditions |
| --- | --- | --- | --- |
| `GET /v0/tags` | — | 200 `TagVocabulary` | 400 `invalidRequest` |
| `GET /v0/tags/{tagId}` | — | 200 `Tag` | 400 `invalidRequest`, 404 `notFound`, 410 `tagDeleted` or `tagMerged` |
| `POST /v0/tags` | `{ "expectedVersion": null, "name": "Research", "color": null }` | 201 created `Tag`, or 200 the existing `Tag` with that normalized name | 400 `invalidRequest`, 413 `metadataTooLarge` |
| `PUT /v0/tags/{tagId}/name` | `{ "expectedVersion": 2, "name": "Reading" }` | 200 resulting `Tag`, which can have the preexisting destination ID | Same as tag read, 409 `staleFieldVersion` with `tag: Tag`, 413 `metadataTooLarge` |
| `PUT /v0/tags/{tagId}/color` | `{ "expectedVersion": 3, "color": "#112233" }` | 200 current `Tag` | Same as tag read, 409 `staleFieldVersion` with `tag: Tag` |
| `POST /v0/tags/{tagId}/delete` | `{ "expectedVersion": 4 }` | 200 `{ "tagId": "<tagId>" }`, including repeats while the deletion tombstone exists | 400 `invalidRequest`, 404 `notFound`, 410 `tagMerged`, 409 `staleFieldVersion` with `tag: Tag` |

- **Create.** An existing normalized name returns the existing ID, name and
  color. Recover a lost response from vocabulary state. A normalized name
  freed by a later delete or rename is available for a new creation.
- **Rename.** Use `nameVersion`. If the normalized destination belongs to
  another live tag, atomically end the source ID and union its assignments
  into the destination. Preserve the destination ID, display name and color.
  Assignments newly added to the destination advance its assignment Field
  Version on that Lineage. If the destination is already assigned, its
  membership is a no-op. The source's assignments disappear in either case.
- **Recolor.** Use `colorVersion`. A concurrent rename of this same live
  tag does not invalidate the color expectation.
- **Delete.** Use the tag's aggregate `version`. Assignments do not advance
  that version. A committed delete removes all memberships for the old ID.
  A concurrent assignment either commits first and is removed or encounters
  the ended ID and is rejected. A tag created later with the same name has
  a new ID, to which old assignment writes never apply.

**Proposed retention.** Keep deletion tombstones for 90 days, then return
404 `notFound`. Keep a merge redirect while its terminal destination is
live. Follow chains to the current live survivor for `tagMerged`. If that
survivor is deleted, the former IDs have the same deletion outcome and
retention as the survivor. This gives an offline Device a way to preserve
local assignments when vocabulary reconciliation catches up after a merge.

## Account Change Feed

The existing `GET /v0/feed` gains two kinds. The existing shape, cursor
semantics and content Lineage entries follow v0.1.

| `kind` | `id` | `version` | Read |
| --- | --- | --- | --- |
| `metadata` | `lineageId` | `LineageMetadata.version` | `GET /v0/lineages/{id}/metadata` |
| `tagVocabulary` | literal `vocabulary` | `TagVocabulary.version` | `GET /v0/tags` |

The feed keeps one latest entry per `(kind, id)`. Every change replaces that
entity's position, and related entries from one transaction have a stable
order. A tag deletion or merge moves the vocabulary entry and the metadata
entries of every affected live Lineage. A first Head Advance makes default
metadata readable without a separate metadata feed entry. Lineage ending
moves the content Lineage entry and drops the metadata entry in the same
transaction. Clients still holding a metadata hint can handle
`lineageEnded` or `notFound`.

A Device reads current state on a newer entry and reconciles it. Vocabulary
must be current enough to resolve the IDs in any assignment snapshot before
applying it. If an ID is missing, read the vocabulary and re-read metadata
when needed. v0.1 clients skip the new kinds and advance their cursor, as
required by v0.1 and implemented by the current Lineage-only filter.
[v0.1 reconciler](../packages/skills_cloud/lib/src/sync/reconciler.dart#L122-L136)

## Library and bootstrap

`GET /v0/library?include=metadata&cursor=<opaque>&limit=<1..500>` opts into a
metadata projection of the existing listing. Without `include=metadata`,
the response follows v0.1. Keep the same projection for every page. An
unsupported `include` value or switching projection within a listing is
400 `invalidRequest`. The other pagination rules and failures are those
of the v0.1 library endpoint.

```json
{
  "lineages": ["Lineage…"],
  "metadata": ["LineageMetadata…"],
  "tagVocabulary": { "version": 5, "tags": ["Tag…"] },
  "next": "<opaque>|null",
  "feedCursor": "<opaque>"
}
```

Every page pairs each returned Lineage with its metadata in the same order,
from the same read. A Lineage before its first Head Advance stays out of
the library, as in v0.1. `tagVocabulary` holds the full vocabulary on the first
page and is null on later pages. The service captures one `feedCursor`
before any of these reads and echoes it on every page. As in v0.1 this is
a lower bound for replay. A change after that cursor may already be reflected
in one read, but is also discoverable by Feed Check. A new Device or reset
reconciles the listing, then consumes the feed from that same cursor, using
entity versions to avoid reapplying older views. A Device enabling v0.2
metadata sync for the first time needs this bootstrap even if it has a v0.1
content cursor.

Apply vocabulary before metadata. If vocabulary and assignments from
different pages no longer agree, refresh current vocabulary and the affected
metadata before sending a complete assignment set to Workspace. Device
Exclusions still skip materialization of the affected Skill and its metadata.

## Ending

Synced Removal and Stop Syncing end metadata writes as part of the existing
v0.1 ending transaction. By proposal, purge cloud Favorites, Notes, Note
Conflicts, retained Note edits and assignments at ending. Keep the v0.1
Lineage tombstone and Generation retention. A stopped Skill keeps each
Device's local Favorite, Note and assignments as Device Only. A removed
Skill follows the existing local Removal policy, including its Draft guard.
The account vocabulary survives either ending. A new Lineage starts with
default metadata and can upload locally retained values as fresh state.

## Client flow (informative)

- Use the Workspace committed-change feed's per-Skill `metadata` kind and
  vocabulary row to trigger Reconciliation. Keep the last reconciled field
  values, Field Versions, and local-to-server tag mapping in `skills_cloud`.
  Dirty state is the difference between current local values and their
  remembered values. On a rejected compare-and-set read current state and
  re-evaluate that difference. If the local value is still dirty, retry
  Favorites, assignments, names and colors against the current version
  without asking. For Notes retain the original base and follow the conflict
  write rule. After any response, re-read the local value before marking it
  reconciled so an edit during the request remains visible.
- Use `RemoteTagVocabulary.ensure(name, color)` before applying assignments
  and record the resulting local ID from `tag(tagId)`. Use
  `update(tagId, name, color)` for a mapped rename, recolor or merge,
  giving it the survivor's current name and color. Use `delete(tagId)` for
  deletion. On a vocabulary refresh, look up known server IDs that vanished
  to distinguish a merge from a deletion. Keep only the surviving mapping
  after merging. Before reusing any local tag with a matching normalized name,
  apply deletions for older IDs that held that name. A recreated name
  should not inherit the previous tag's assignments.
- Send `RemoteSkillMetadata(managedSkillId, expectedEffective, favorite,
  note, tagIds)` after content installation and when reconciling metadata.
  Pass the entire set of mapped local IDs. Preserve a still-dirty local
  field when applying another field. `metadataApplied` and `noChange`
  are both successful outcomes. A stale Effective requires a fresh
  Workspace read before retry. The Effective guard alone cannot detect an
  intervening local metadata edit. See the open question on local write
  serialization. Field Versions and server IDs stay in `skills_cloud`.
- Show the existing Note Conflict Attention Reason when a linked Skill's
  current `note.conflict` is non-null. Leave the person's local Note in
  place until they choose a text or combine the candidates. A Device with no
  local Note may apply `note.value` while showing the candidates. Once the
  conflict clears, reconcile the resolved Note. A distinct pending local
  edit from a third Device still follows the same base comparison. Favorites
  and tags continue syncing while the Note awaits a choice.

## Binding decisions and where they are specified

| Binding rule | Section |
| --- | --- |
| Every synced value has a Field Version and writes use compare-and-set | [Conventions and Field Versions](#conventions-and-field-versions), [Objects](#objects) |
| Favorites, Tag Assignments, tag names and colors settle in server acceptance order without asking | [Conventions and Field Versions](#conventions-and-field-versions), [Client flow](#client-flow-informative) |
| Different Note texts from one Field Version form a conflict and survive until resolution | [Note writes and resolution](#note-writes-and-resolution) |
| Create returns the tag with the existing normalized name | [Normalization and proposed limits](#normalization-and-proposed-limits), [Vocabulary endpoints](#vocabulary-endpoints) |
| Rename onto an existing name merges assignments into that tag | [Vocabulary endpoints](#vocabulary-endpoints) |
| Tag deletion wins over concurrent assignment | [Vocabulary endpoints](#vocabulary-endpoints) |
| Workspace receives local IDs and no Field Versions, with mapping in `skills_cloud` | [Client flow](#client-flow-informative) |

## Open questions for the maintainer

| Question | Recommended answer and reason |
| --- | --- |
| How should very late Note edits form a conflict? | Prefer retaining only the latest accepted transition and comparing older submissions with the current committed text. This preserves the pending local and current texts with bounded storage but may omit the historical text originally accepted from that same base. If the product requires the exact historical pair for every delayed Device, use the proposed retention above and accept the additional private history and recognition data. Confirm which meaning of the R5 guarantee applies before T33. |
| How should a third Note candidate or a newer intervening Note be handled? | Present the original pair and keep the current committed Note visible. Leave further edits in their Workspaces until the open pair is resolved. This keeps one server conflict record per Note and preserves each Device's choice. |
| What survives a tag merge? | Keep the destination name and color and retain the source redirect as long as there is a live survivor. This lets offline Devices transfer local assignments even when they missed the rename. Purge deletion tombstones at 90 days. |
| How should bootstrap carry metadata? | Use the opt-in projection and one v0.1 replay cursor. This keeps older responses compatible and avoids storing multi-page snapshots. |
| What happens to personal data when a Lineage ends? | Purge cloud metadata immediately, with the existing v0.1 tombstone and pack retention. Stop Syncing keeps each Device's local data. This avoids keeping private text on a tombstone. |
| How should the client protect a local write between reading and applying metadata? | Serialize App metadata edits with its apply step. T34 should check whether another supported Workspace writer can bypass that guard. If so, review an expected-local-values guard separately before changing the M5 API. It would compare local values. |
| Are the proposed 4 KiB, 64 scalar values and 256 tag limits suitable? | Start with these bounds. Preflight limits on Cloud-aware edits, surface quota with `storageLimitReached`, and give preexisting oversized Notes or tags an edit-to-fit action. A Note needs a Skill Attention Reason and a vocabulary limit on an existing name needs an account-level correction. Accept that R10 presentation before enabling metadata sync so rejected data does not stay pending indefinitely. |
