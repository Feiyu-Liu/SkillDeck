# ExecPlan: T28 Draft Cloud API contract v0.2: metadata, tags, and Note Conflict

Milestone M6, design only. Codex drafts the contract; the maintainer accepts
it before T33 (service) and T34 (client) are written. No code. Simplicity
rules: see `../execplan-template.md`.

## Set by the planner

### Goal

A draft `../cloud-api-contract-v0.2.md` that adds synced metadata to v0.1:
Favorites, Notes with Note Conflict, Skill Tag Assignments, and the Synced Tag
Vocabulary. Its points are each settled, or listed as an open question with a
recommended answer.

### Context

- **Read first:**
  - `../phase1-plan.md`, the decision on Metadata (R5);
  - `packages/skills_cloud/CONTEXT.md`: Field Version, Note Conflict, Synced
    Tag Vocabulary, and the rules list around "compare-and-set";
  - `../m5-sync-apply-contract.md`: `RemoteSkillMetadata`,
    `RemoteTagVocabulary`, `metadataApplied`, `tag(tagId)`, and the
    committed-change feed's `metadata` kind and vocabulary row;
  - `../cloud-api-contract-v0.1.md`, whose conventions, error shape, feed, and
    account sharding v0.2 extends;
  - `../cloud-api-contract-v0.md`, the conventions.
- **Binding rules from R5 and CONTEXT.md:**
  - every synced value has a Field Version, and every write is a
    compare-and-set on it;
  - Favorites, Tag Assignments, tag names, and tag colors settle in server
    acceptance order, without asking the person;
  - two different Note texts written from the same Field Version form a Note
    Conflict that keeps both texts until the person chooses one or combines
    them;
  - creating a tag whose normalized name exists returns the existing tag;
    renaming onto an existing name merges assignments into the existing tag;
    deleting a tag wins over a concurrent assignment;
  - the Workspace never sees Field Versions or server tag IDs. `skills_cloud`
    keeps the server-tag to local-tag mapping.

### Contract

The draft must define, in the style of v0.1:

- **Objects:** the metadata of one Lineage (Favorite, Note, the set of
  assigned tag IDs, each with its Field Version), a tag (server ID, name,
  normalized name, color `#RRGGBB` or null, Field Version), and a Note Conflict
  (both texts, the Field Version they came from, and the Devices).
- **Endpoints:** reads and compare-and-set writes for each value, the
  vocabulary list, tag create, rename, recolor, and delete, and resolving a
  Note Conflict. Request and response bodies, and an error table for each.
- **Normalization:** the tag-name normalization rule. Check
  `packages/skills_workspace` for the local rule and use the same one, citing
  the file.
- **Feed:** how metadata and vocabulary changes reach other Devices, with v0.1's
  one-entry-per-entity rule. Say whether they get new entry kinds, and confirm
  that a v0.1 client skips them.
- **Library and bootstrap:** how a new Device gets all metadata and the whole
  vocabulary with one consistent `feedCursor`.
- **Ending:** what happens to metadata when a Lineage is removed or stopped,
  and to assignments when a tag is deleted.
- **Limits:** the Note's maximum size, the tag name's maximum length, and the
  number of tags per account. Propose values, and mark each as a proposal.
- **Client flow (informative):** compare-and-set retries, mapping to
  `RemoteSkillMetadata` and `RemoteTagVocabulary`, and when a Note Conflict
  becomes the "Note Conflict" Attention Reason.
- **Decided points and open questions:** a list at the end. Each open question
  gets a recommended answer and its reason.

### Acceptance

- The draft names every endpoint, field, error code, and limit it uses.
- Each binding rule above maps to a section of the draft; add a table that
  lists rule → section.
- No rule in v0 or v0.1 changes. If one has to, it is an open question.
- `../README.md` gains a row for the draft, marked "Draft, awaiting the
  maintainer".
- No code changes in any package.

### Scope fence

- **In scope:** `branch-doc/cloud-api-contract-v0.2.md` and the README row.
- **Out of scope:** service and client code; the App; Individual Sharing and
  later phases.

### Stop and ask if

- A binding rule above cannot be met without a realtime channel, a client
  outbox, or a Workspace API that names Field Versions.
- The local tag normalization rule is unclear or differs between call sites.

## Maintained by Codex

### Progress

- [x] Read the binding decisions, v0 and v0.1, and Workspace apply contract.
- [x] Verify the Workspace normalization helper and the v0.1 feed filter.
- [x] Draft v0.2 and add its draft row to the README.

### Decision Log

- Proposed two metadata feed kinds and a bootstrap projection with the
  existing v0.1 replay cursor.
- Proposed independent name and color Field Versions and a tag version for
  deletion. Merge redirects let offline Devices transfer local assignments.
- Proposed a Note conflict write guarded by the current Field Version and
  tied to the original base. The original accepted edit is retained so
  delayed Devices can present the exact pair.

### Surprises

- The local normalization helper is shared across create, update, lookup
  and remote vocabulary apply. Its Dart case and trim behavior needs
  equivalent service behavior.
- A late Note edit can arrive after several other edits. The draft calls
  out the retention cost of accurately recovering its competing edit.
- M5 guards metadata apply with the Effective Revision. It cannot detect
  a concurrent local edit that changes only metadata.

### Follow-ups

- The maintainer accepted the revised contract and current-value Note policy on
  2026-11-27. T33/T34 implementation and validation completed on 2026-11-28.

### Outcome

- Design draft ready for review. v0 and v0.1 are untouched, with no
  service, client, Workspace or App implementation in this task.

The earlier retention proposal above was superseded by the accepted v0.2
revision; current behavior and evidence are recorded under T33/T34.
