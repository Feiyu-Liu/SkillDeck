# ExecPlan: T43 Sync attention, notices, and Settings: say what happens, offer one next step

First rework card from the T39 audit, items 1, 2, and 5 of
`../reviews/2026-11-28-t35-t39-review.md`. App only. Simplicity rules **and UI
rules**: see `../execplan-template.md`. **Use only the text below.** Every
state, button, and dialog is listed. If you meet one that is not, stop and ask.

## Set by the planner

### Goal

- Every Sync attention state on a Skill:
  - says in one plain sentence what happened;
  - offers at most one primary and one secondary action;
  - confirms an action, before it runs, with what will happen to the
    person's work.
- No Cloud notice is a dead end.

### Context

- **Read first:**
  - `../reviews/2026-11-28-cloud-ui-inventory.md` and its screenshots;
  - `lib/features/cloud/presentation/widgets/cloud_attention_actions.dart`;
  - `cloud_skill_sync.dart`;
  - `_CloudSyncNoticeBanner` in `lib/app/skills_manager_app.dart`;
  - `cloud_sign_in_settings.dart`;
  - the Reconciler actions that these buttons call.
- **Maintainer decisions, 2026-11-28:**
  - **"Use the new source"** (today's "Accept replacement") removes the
    device's old history and unsynced revisions. Revised after implementation
    review with explicit maintainer approval; preservation is a separate task.
  - **"Keep on this device only"** means the Skill stops syncing on this
    device.
  - **Too large:** offer only "Stop syncing". Drop "Keep on this Device only"
    there.
  - **Missing after a reset:** offer "Upload again" and "Keep on this device
    only". Drop "Remove here"; the person can delete the Skill the usual way.
  - **Incoming update with a Draft:** the review dialog becomes the place
    where the Draft is discarded.
  - **File names such as `SKILL.md`** stay in change reviews. Skill authors
    read them.
- **"Device" stays the word,** not "Mac", because Windows will share these
  strings.

### Contract

#### Facts to verify before changing text

Check each fact below and write the result in the Decision Log, with the test
or code that shows it. **If any one is false, stop and ask.** The text below
depends on it.

1. After `acceptReplacement`, this device's earlier revisions are still in the
   Skill's history in the App.
2. After `keepDeviceOnly`, turning "Sync to Cloud" back on uploads the Skill
   as a new Cloud entry. It does not rejoin the old one.
3. After `stopSyncing`, other devices keep their copy of the Skill, and it
   becomes Device Only there.
4. After a conflict is resolved, the version not kept is still in the Skill's
   history.
5. `removeMissingLocally` removes the Skill and its local history from this
   device.

#### Attention states on the Skill detail

In each state, the status line shows the "Text"; the buttons sit under it,
primary first. The table replaces today's rows. Any key not used afterwards is
deleted from both ARB files.

| Reason | Text (EN / ZH) | Primary | Secondary |
| --- | --- | --- | --- |
| incomingDraft | "Another device updated this Skill. You have a Draft here, so the update is waiting." / "另一台设备更新了此 Skill。这里有草稿，所以更新还在等待。" | "Review update" / "查看更新" → the incoming review dialog below | "Publish Draft" / "发布草稿" (no confirmation; as today) |
| syncMergeConflict | "This Skill was changed on two devices." / "此 Skill 在两台设备上都有修改。" | "Resolve" / "解决冲突" → the conflict dialog below | none |
| removedWithDraft | "Another device removed this Skill. You have an unpublished Draft here." / "另一台设备已删除此 Skill，这里还有未发布的草稿。" | "Keep on this device" / "保留在这台设备" → confirmation K | "Remove from this device" / "从这台设备移除" → confirmation R1 |
| sourceReplacedWithLocalChanges | "Another device switched this Skill to a new source. Changes on this device haven't synced." / "另一台设备把此 Skill 换成了新的来源，这台设备上的更改还没有同步。" | "Use the new source" / "使用新来源" → confirmation N | "Keep on this device" / "保留在这台设备" → confirmation K |
| slotOccupied (on the local Skill) | "A synced Skill has the same name as this Skill." / "有一个已同步的 Skill 与此 Skill 同名。" | "Keep this Skill" / "保留此 Skill" (today's exclude; no confirmation) | "Replace with synced Skill" / "换成已同步的 Skill" → confirmation S |
| tooLarge | "This Skill is too large to sync. Make it smaller, or stop syncing it." / "此 Skill 太大，无法同步。请减小它的体积，或停止同步。" | "Stop syncing" / "停止同步" → confirmation T | none |
| missingAfterReset | "This Skill is no longer in your SkillDeck Cloud library." / "此 Skill 已不在你的 SkillDeck Cloud 资料库中。" | "Upload again" / "重新上传" (no confirmation) | "Keep on this device" / "保留在这台设备" → confirmation K |

- **An action fails:** show the existing failure line under the buttons, with
  the new text "Couldn't finish. Try again." / "未能完成，请重试。". The same
  buttons stay.
- **`slotOccupied` without a resolvable Cloud entry** has no actions today, so
  it is a dead end. Find when it happens and record it in Surprises.
  - If the state can be shown to a person, stop and ask.
  - If it cannot, show nothing for it.
- **Remove** today's separate caption (`cloudOccupiedLocalSlot`). The row text
  above replaces it.

#### Confirmations

Use the existing `showAppConfirmDialog`. The danger style is for R1 and S only;
the others use the normal style.

| Id | Title (EN / ZH) | Message (EN / ZH) | Confirm (EN / ZH) |
| --- | --- | --- | --- |
| K | "Keep on this device only?" / "仅保留在这台设备？" | "This Skill stops syncing on this device. If you turn sync on again later, it's uploaded as a separate Skill." / "此 Skill 将在这台设备上停止同步。之后再开启同步，它会作为另一个 Skill 上传。" | "Keep on this device" / "保留在这台设备" |
| R1 | "Remove from this device?" / "从这台设备移除？" | "The Skill, its Draft, and its history are removed from this device. This can't be undone." / "此 Skill、它的草稿和历史记录都会从这台设备移除，且无法撤销。" | "Remove" / "移除" |
| N | "Use the new source?" / "使用新来源？" | "This device's unsynced changes and previous history will be removed and replaced by the new source's history." / "这台设备上未同步的更改和原有历史记录将被移除，由新来源的历史记录代替。" | "Use new source" / "使用新来源" |
| S | "Replace with the synced Skill?" / "换成已同步的 Skill？" | "This Skill and its history are removed from this device, and the synced Skill takes its place." / "此 Skill 及其历史记录会从这台设备移除，由已同步的 Skill 代替。" | "Replace" / "替换" |
| T | "Stop syncing this Skill?" / "停止同步此 Skill？" | "It stays on this device and your other devices, but changes no longer sync." / "它会保留在这台设备和你的其他设备上，但更改不再同步。" | "Stop syncing" / "停止同步" |

Cancel is the dialog's existing "Cancel" / "取消". Cancelling changes nothing
and shows nothing.

#### The incoming review dialog (incomingDraft)

- **Header title:** "Update from another device" / "来自另一台设备的更新".
- **Top line:** "Updating replaces your Draft with this version. Your Draft
  can't be recovered." / "更新会用这个版本替换你的草稿，草稿将无法恢复。"
- **Body:** the diff, as today, with its file names.
- **Footer:**
  - secondary "Cancel" / "取消";
  - primary, danger style, "Discard Draft and update" / "丢弃草稿并更新".
    It runs today's discard, after which the update applies. No second
    confirmation.
- **The empty and binary states** keep their texts: "No file changes." and
  "Binary file changed.".

#### The conflict dialog (syncMergeConflict)

- **While choosing:**
  - header title "Resolve conflict" / "解决冲突";
  - subtitle "The same files were changed on two devices. Choose which
    version to keep. The other version stays in this Skill's history." /
    "两台设备修改了相同的文件。请选择要保留的版本，另一个版本会留在此 Skill 的历史记录中。".
  - Footer buttons, all secondary, in this order:
    - "Cancel" / "取消";
    - "Keep the other device's version" / "保留另一台设备的版本";
    - "Keep this device's version" / "保留这台设备的版本".
  - **The one allowed exception to rule 4:** two equal choices are not
    primary and secondary. Record it in the Decision Log.
- **After choosing:**
  - subtitle "Check the merged Draft, then publish it." /
    "请检查合并后的草稿，然后发布。";
  - footer: secondary "Close" / "关闭", primary "Publish" / "发布".
  - Remove "Show Draft in Finder" from this dialog.

#### Notices (bottom left of the window)

| Notice | Text (EN / ZH) | Action |
| --- | --- | --- |
| stopped | "Sync stopped because of a problem on this device. Your Skills here are safe." / "同步因这台设备上的问题而停止。这里的 Skill 不受影响。" | a small primary `AppButton` "Try again" / "重试" in the notice, which restarts Cloud sync for the signed-in account. If it stops again, the notice shows again. |
| storageLimit | "Your SkillDeck Cloud storage is full. New changes stay on this device until there's room." / "你的 SkillDeck Cloud 存储空间已满。新的更改会先保存在这台设备上，有空间后再同步。" | none. This is a status, not a failure. The maintainer will add an action when quotas are set. Record it as a Follow-up. |

#### Settings, Cloud section

- **Offline:** "Try again" / "重试" becomes the primary button. "Sign out"
  stays secondary. Text unchanged.
- **Metadata unavailable:** the text becomes "Favorites, notes, and tags don't
  sync with this server yet. Skills still sync." /
  "此服务器暂不同步收藏、备注和标签，Skill 本身仍会同步。". No action.

### Acceptance

- **Widget tests:**
  - every row of every table renders exactly its text and buttons, in EN and
    ZH;
  - each button calls the right action;
  - each confirmation's cancel changes nothing;
  - the notice's "Try again" restarts sync, and a repeat failure shows the
    notice again.
- **A search** of `lib/` and both ARB files finds:
  - no "slot" in English UI text, and no "槽位" or "位置" in the Cloud strings;
  - no "Lineage";
  - none of the deleted keys.
- **Screenshots** (UI rule 8), in `branch-doc/screenshots/T43/`:
  - every state, dialog, and confirmation above, in EN and ZH, light and
    dark;
  - capture them by extending T39's capture code.
- **The Decision Log** has the five verified facts.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code, and
  the macOS desktop E2E suite.

### Scope fence

- **In scope:**
  - the Cloud presentation widgets;
  - the notice banner;
  - the Cloud Settings rows;
  - the ARB files and generated localizations;
  - a runtime restart method if none exists;
  - tests and capture code.
- **Out of scope:**
  - note conflicts, the new-Device sheet, and tag limits (T44);
  - sign-in (T41, T42);
  - `skills_cloud` behaviour;
  - the Skill row marks.
- **Expected size:** about 8–12 files, 600–1,200 lines with tests and
  generated code.

### Stop and ask if

- Any of the five facts is false.
- Restarting sync needs a change in `skills_cloud`.
- A state appears that these tables do not cover.

## Maintained by Codex

### Progress

- Implemented and validated on 2026-11-28; see the combined report below.

### Decision Log

- 2026-11-28: Fact 1 is false. `remote_source_replacement_preparation.dart`
  prepares the new store and `destructive_operation_planner.dart:193` deletes
  old lineages. Maintainer approved retaining behavior, warning that old local
  history/unsynced changes are removed, and tracking preservation separately in
  `../follow-ups/source-replacement-history.md`. Confirmation N now says:
  "This device's unsynced changes and previous history will be removed and
  replaced by the new source's history." / "这台设备上未同步的更改和原有历史记录将被移除，由新来源的历史记录代替。"
- Fact 2: `keepDeviceOnly` excludes/unlinks; `startSyncing` creates a new
  client key when no link exists (`reconciler.dart`). No old lineage is rejoined.
- Fact 3: a stopped remote lineage only unlinks the local copy
  (`reconciler.dart`, `LineageState.stopped` branch); it does not remove content.
- Fact 4: remote conflict resolution creates a candidate commit with both
  previousEffective and remoteParent (`candidate_conflict_preparation.dart`);
  publishing retains that ancestry.
- Fact 5: `removeMissingLocally` calls guarded Workspace removal; the
  destructive planner deletes the Managed Skill aggregate and its stores.
- Conflict-side buttons are equal content choices, the card's explicit rule-4
  exception. Incoming review uses the existing equal-width footer to keep its
  longer action inside the dialog. Conflict choices use bounded Flexible actions
  in a 620 px dialog, preserving full labels at the default native window size.

### Surprises

- The null-lineage action switch branch is unreachable: `_attention` returns
  a slot conflict only from an outcome entry with a non-null map key or link ID.
  The real Workspace adapter supplies an occupant ID; unresolved synthetic
  states do not render actions.

### Follow-ups

- Storage-limit status has no recovery action until quota policy is defined.
- Source-replacement history: see the separate follow-up above.

### Outcome

Implemented. See `../validation/t41-t44-2026-11-28.md` for per-command gates,
native and staging acceptance, screenshot paths, approved deviations and limits.
