# ExecPlan: T09 Applying remote metadata, Removal, and tag vocabulary

Milestone M5, last card. Builds on T06, T07, T08, T11, and T12. Plan:
`../phase1-plan.md`. Contract: `../m5-sync-apply-contract.md`, sections
"Request variants", "Results", "Other variants" (Metadata, Removal,
Vocabulary), and "Where each R10 Attention Reason comes from". Simplicity
rules: see `../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` can apply three more kinds of remote change through
`applyRemoteState`, each in one local transaction:

- a Skill's final Favorite, Note, and Tag Assignments;
- a Synced Removal;
- a change to the tag vocabulary.

A Dirty Draft or an Update Candidate Session blocks a Removal, and the
Workspace reports that as the R10 Attention Reason.

### Context

- **Decisions:**
  - R4: Synced Removal applies without asking, except that a Dirty Draft or an
    Update Candidate Session blocks it for that Skill.
  - R5: `skills_cloud` settles Field Versions and Note Conflicts before it
    calls the Workspace. The Workspace receives final values only and never
    sees Field Versions, server tag IDs, or conflicts.
  - Contract: `skills_cloud` maps server tags to local tag IDs, using
    `ensure` to create them.
- **Closest flows,** under `packages/skills_workspace/lib/src/`:
  - **Library:** `application/library/library_mutation_planner.dart` and its
    handlers in `composition/metadata_command_handlers.dart` (`_runLibrary`).
    They already hold the rules for Notes (trimmed, never empty), Favorites,
    assignments, and tag-name normalization, and they emit the business
    changes that the committed-change feed (T06) reads.
  - **Removal:** `application/destructive/destructive_operation_planner.dart`
    and `composition/destructive_command_handlers.dart`. Local Removal already
    refuses a Dirty Draft or an Update Candidate Session, and checks a
    reviewed RepositoryRevision.
  - **Remote command:** `composition/remote_content_command.dart`, after T08.
    It already dispatches on the request variant, and it returns results that
    change nothing through `OperationPreparationUnchanged`, with no Operation
    Record.
- **Feed:** T06 derives `metadata`, `removed`, and `vocabularyChanged` from
  the business changes. That includes the assignments a tag deletion cascades
  to. Reuse the same changes and the feed follows.

### Contract

Names are provisional.

- **New request variants of `ApplyRemoteStateRequest`:**
  - `RemoteSkillMetadata`, with:
    - `managedSkillId` and `expectedEffective`;
    - `favorite: bool`;
    - `note: String?`, where null clears the Note, and a value that is empty
      after trimming throws `ArgumentError`;
    - `tagIds`, the complete set of local tag IDs.
  - `RemoteSkillRemoval`, with `managedSkillId` and `expectedEffective`.
  - `RemoteTagVocabulary`, as three cases: `ensure(name)`,
    `rename(tagId, name)`, and `delete(tagId)`.
- **New results:** `removed` and `tag(tagId)`.
- **Metadata:**
  - the guard runs first. A different current Effective gives `staleSnapshot`
    with `reason: effectiveRevisionChanged`, as in T07;
  - the Favorite, Note, and assignment set become exactly the given values, in
    one Business Commit;
  - when every value already matches, the result is `noChange`, with no
    revision bump and no Operation Record;
  - an unknown tag ID gives `personalTagNotFound`, and nothing changes;
  - a Draft or an Update Candidate Session does not block metadata.
- **Removal:**
  - the guard runs first, as above. It replaces the reviewed RepositoryRevision
    of local Removal;
  - a Dirty Draft or an Update Candidate Session gives
    `draftResolutionRequired`. That is a successful result that changes
    nothing and leaves no Operation Record;
  - otherwise the Skill is removed as local Removal does, including its
    Activations, and the result is `removed`;
  - an unknown or already removed Skill gives `skillNotFound`. `skills_cloud`
    treats that as done on retry.
- **Vocabulary:** no guard. The local normalization rules apply.
  - `ensure(name)`:
    - if a tag with that normalized name exists, the result is `tag(id)` of
      that tag and nothing changes;
    - otherwise a tag with no color is created, and the result is `tag(newId)`.
  - `rename(tagId, name)`:
    - the same normalized name as the tag's own gives `tag(tagId)`, and only
      the display name changes, if it differs;
    - a name that another tag already has moves every assignment into that
      tag, deletes the renamed tag, and gives `tag(otherId)`, in one Business
      Commit;
    - an unknown `tagId` gives `personalTagNotFound`.
  - `delete(tagId)`: removes the tag and its assignments, and gives `removed`.
    An unknown `tagId` gives `noChange`, so a retry is safe.
- **Tag colors are local only.** The confirmed contract syncs tag names, not
  colors:
  - `rename` keeps the tag's color, unlike `updatePersonalTag`, which sets it;
  - a merge keeps the color of the tag it merges into;
  - `ensure` creates a tag with no color.
- **Review item T08-2:** a Source payload encoding failure in remote install
  maps to the same code that local install uses (`invalidSkill`), not
  `transportRejected`.

### Acceptance

Each item is a test through the public API with the existing facade fixtures.

- **Metadata:**
  - setting all three fields:
    - changes the snapshot;
    - bumps the revision once;
    - gives one feed entry with exactly `{metadata}`.
  - a null Note clears the Note, and an empty Note throws `ArgumentError`;
  - an assignment set smaller than the current one removes the missing
    assignments;
  - repeating the same request gives `noChange`, with no revision bump and no
    Operation Record;
  - a stale `expectedEffective` and an unknown tag each leave state unchanged;
  - it succeeds while the Skill has a Dirty Draft.
- **Removal:**
  - it removes the Skill, its Repository Copy, and its Activations;
  - the feed reports `removed`;
  - with a Dirty Draft, and with an open Update Candidate Session, it gives
    `draftResolutionRequired`, and the Skill, the operation history, and the
    journal are unchanged;
  - a stale guard leaves state unchanged;
  - a retry after success gives `skillNotFound`;
  - a crash before and after the Business Commit Point recovers to "present"
    and "removed" respectively, with the existing destructive crash harness.
- **Vocabulary:**
  - `ensure`:
    - a new name gives a new tag;
    - the same name in different case or spacing gives the existing tag
      with no revision bump.
  - `rename`:
    - a plain rename keeps the tag's color;
    - a rename onto an existing name:
      - moves the assignments, including a Skill that had both tags, which
        ends with one assignment;
      - deletes the renamed tag;
      - reports `vocabularyChanged` and `metadata` for each affected Skill.
  - `delete`:
    - it removes the assignments, and the feed reports them;
    - repeating it gives `noChange`.
- **T08-2:** a test for the corrected code.
- **Gates:** the T01 gates. Report each command's own exit code.

### Scope fence

- **In scope:** `packages/skills_workspace/`. The contract already matches
  this card: `delete` gives `removed` or `noChange`, and colors stay local.
- **Out of scope:**
  - Field Versions, Note Conflicts, and server tag mapping, which belong to
    `skills_cloud` (M6);
  - syncing tag colors;
  - Generation changes;
  - review item T13-1, remote ancestry after a Store loss;
  - App changes;
  - native and schema changes.
- **Expected size:** about 12–20 files, 800–1,400 lines including tests. If
  it grows well past that, stop and propose a split, for example Removal on
  its own.

### Stop and ask if

- Removal through the remote path needs a new journal phase, recovery entry
  kind, or schema change.
- Bypassing the reviewed RepositoryRevision would mean adding a remote flag
  to the destructive planner. Say how you would avoid that first.
- A rename merge cannot be one Business Commit with the existing library
  changes.
- The feed would not report a cascaded assignment change with the existing
  business changes.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
