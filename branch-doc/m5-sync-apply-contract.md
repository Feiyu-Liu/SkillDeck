# M5 contract: applying remote state and the committed-change feed

Status: confirmed by the maintainer, 2026-11-24, including the two points marked
below. It fixes the public shape
of R11 seams 3 and 4. Task cards T06–T09 implement it. Names are provisional;
shapes are not.

Decisions behind it: R3, R4, R5, R6, R10, and R11 of the ADR-0105 revision, and
the maintainer decisions of 2026-11-24:

- The committed-change feed keeps only the latest entry per Skill.
- A new Device installs straight from a pack file.
- `skills_cloud` maps server tags to local tag IDs.

## What the Workspace knows and does not know

- **Knows:** Managed Skill IDs, `RevisionId`s, Source Descriptors, local Personal
  Tag IDs, and final metadata values.
- **Never knows:** Cloud Lineages, Generations, Field Versions, Note Conflicts,
  Sync Status, server tag IDs, URLs, or credentials.
  - `skills_cloud` keeps the mapping from Cloud Lineage to Managed Skill ID, and
    from server tag to local tag ID.
  - `skills_cloud` settles every Note Conflict before it calls the Workspace,
    then passes only the final text.
- **Retry safety:** every call is safe to repeat. A repeated call either finds
  the state already applied (`noChange`) or fails the guard (stale). Nothing is
  remembered about callers.

## Seam 4: committed-change feed (T06)

- `inspectCommittedChanges(since: RepositoryRevision)` is a read operation. It
  returns one of:
  - **`changes(current, entries)`:** `current` is the RepositoryRevision the read
    saw. `entries` lists every Skill whose latest recorded change is after
    `since`. Each entry holds the `ManagedSkillId`, the revision of that change,
    and its kinds: any of `content`, `metadata`, and `removed`. One further
    entry reports a change to the tag vocabulary.
  - **`resetRequired(current)`:** `since` is greater than `current`. This
    happens when startup recovery restored an older control plane. The caller
    then reconciles every linked Skill.
- **Storage:**
  - A schema v5 table holds one row per Managed Skill ID, plus one vocabulary
    row.
  - Rows are written in the same SQLite transaction that commits the business
    change, so the feed can never disagree with committed state.
  - A removed Skill keeps its row, marked `removed`, so a caller that has not
    yet observed the Removal still sees it.
- **What counts:**
  - `content` means the Skill's Effective or Upstream Revision changed, or the
    Skill was created.
  - `metadata` means its Favorite, Note, or Tag Assignments changed.
  - The vocabulary row changes when a tag is created, renamed, or deleted.

## Seam 3: apply remote state (T07–T09)

There is one public operation,
`applyRemoteState(ApplyRemoteStateRequest) → SkillsOperation<RemoteApplyResult>`.
Each call runs as one Workspace transaction through the existing operation
coordinator, with the usual journal, recovery, and finalization.

### Request variants

| Variant | Fields | Card |
| --- | --- | --- |
| `RemoteSkillContent` | `managedSkillId`, `expectedEffective`, target `effective` and `upstream`, optional `packPath` | T07 |
| `RemoteSkillInstall` | `packPath`, `effective`, `upstream`, `source` (Git, Well-known, or Synced Origin descriptor), optional initial metadata | T08 |
| `RemoteSkillMetadata` | `managedSkillId`, `expectedEffective`, `favorite`, `note` (null clears it), `tagIds` (the complete set of local tag IDs) | T09 |
| `RemoteSkillRemoval` | `managedSkillId`, `expectedEffective` | T09 |
| `RemoteTagVocabulary` | one of `ensure(name)`, `rename(tagId, name)`, or `delete(tagId)` | T09 |

`expectedEffective`, `effective`, and `upstream` are `RevisionId`s.

### Results

| Result | Meaning |
| --- | --- |
| `noChange` | The local state already equals or contains the target. When the target is an ancestor of local, `skills_cloud` Uploads instead |
| `fastForwarded` | The Effective Revision moved to the target commit. No commit was created |
| `merged(newEffective)` | A clean Sync Merge was published. `skills_cloud` Uploads `newEffective` |
| `conflicted` | The Sync Merge conflicted. An Update Candidate Session now exists |
| `draftResolutionRequired` | A Dirty Draft or an Update Candidate Session blocks this Skill |
| `skillSlotOccupied(occupant)` | Install only: a different local Skill holds the Skill Slot |
| `installed(managedSkillId)` | Install succeeded |
| `removed` | Removal succeeded |
| `tag(tagId)` | Vocabulary `ensure` and `rename` return the resulting local tag |

**Deviation from R11, confirmed 2026-11-24:** R11 lists six outcomes. `installed`,
`removed`, and `tag` are added, because their callers need the resulting
identity or confirmation.

**Expected failures**, all as typed failures with existing codes:
- the `expectedEffective` guard fails: `staleSnapshot` with
  `reason: effectiveRevisionChanged`;
- unknown Skill: `skillNotFound`;
- missing or incomplete objects: `revisionStoreCorrupt`, or the T02 import
  outcomes when `packPath` is given;
- cancellation: `operationCancelled`.

### Content rules (R3, R4)

Let L be the local Effective Revision and R the target `effective`.

1. **Blocked Skill:** a Dirty Draft or an existing Update Candidate Session
   returns `draftResolutionRequired`, with no change. Other Skills are
   unaffected.
2. **Content decision:**

   | Case | Result |
   | --- | --- |
   | L = R | `noChange` |
   | L is an ancestor of R | Fast-forward. Move the pointer to R, re-materialize Repository Copy and Activations, re-anchor a clean Draft |
   | R is an ancestor of L | `noChange` |
   | Otherwise | Three-way merge with base = merge-base(L, R), ours = L, theirs = R |

3. **Merge outcomes:**
   - **clean and valid:** publish a merge commit with parents `[L, R]`, then
     return `merged`;
   - **conflicting:** create an Update Candidate Session through the existing
     conflict review, then return `conflicted`;
   - **invalid tree:** the existing validation failure.
4. **Upstream:** let U be the local Upstream and V the target `upstream`. If one
   descends from the other, keep the descendant. Otherwise keep V, the side
   from the Lineage Head.
5. **Objects:** objects come from the live Store plus this Skill's pack
   staging.
   - When `packPath` is given, the pack is first imported as in T02.
   - Staged objects enter the live Store only inside the transaction, as a
     recovery entry, so a rollback leaves the live Store as it was.
   - After commit, the Skill's used staging is removed.

### Other variants (T08, T09, outline only)

- **Install:**
  - verifies the pack, then creates the Store from it rather than from a tree;
  - creates the managed Skill with the given Source Descriptor and selects
    `effective` and `upstream`;
  - creates no Activations (R6);
  - returns `skillSlotOccupied` instead of the install flow's
    `sourceReplacementRequired`.
- **Metadata:** sets the Favorite, Note, and Tag Assignment set to the given
  values. It is guarded by `expectedEffective` and does nothing when the values
  already match.
- **Removal:**
  - follows the existing Removal path, guarded by `expectedEffective` instead
    of a reviewed RepositoryRevision;
  - a Dirty Draft or an Update Candidate Session returns
    `draftResolutionRequired`. That becomes the R10 Attention Reason "Removed on
    another Device while a Draft exists here".
- **Vocabulary:**
  - `ensure` returns the existing tag when the normalized name exists;
  - `rename` onto an existing normalized name moves the assignments into that
    tag and deletes the renamed one;
  - `delete` removes the tag and its assignments.
  - The local tags' existing normalization rules apply.

## Where each R10 Attention Reason comes from

| Attention Reason | Workspace signal |
| --- | --- |
| Incoming change waits behind a Draft | `draftResolutionRequired` on content |
| Sync Merge conflict | `conflicted` |
| Note Conflict | none, because `skills_cloud` detects it |
| Skill Slot occupied by a different local Skill | `skillSlotOccupied` |
| Removed on another Device while a Draft exists here | `draftResolutionRequired` on Removal |
| Source replaced on another Device while this Device has unsynced revisions | none in M5, because it is a Generation change and Generation changes are not in this contract |
| Missing from the Cloud Library after a reset | none, because `skills_cloud` detects it |

Generation changes, which represent Source Replacement, are not covered by this
contract (confirmed 2026-11-24). They are left for a later card once M4 has fixed how `skills_cloud`
detects them.
