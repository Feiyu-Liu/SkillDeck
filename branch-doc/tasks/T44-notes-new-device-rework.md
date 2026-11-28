# ExecPlan: T44 Note conflicts, the new-Device sheet, and limit messages

Second rework card from the T39 audit, items 3, 4, and 5 of
`../reviews/2026-11-28-t35-t39-review.md`. App only. It can run in parallel
with T43; if both touch the ARB files, rebase and regenerate. Simplicity rules
**and UI rules**: see `../execplan-template.md`. **Use only the text below.**

## Set by the planner

### Goal

- **Note conflicts:** a person can see every version, start from a text that
  loses nothing, edit it with the editor fully visible, and save it.
- **The new-Device sheet** shows people names, not paths.
- **Limit messages** use no technical units.

### Context

- **Read first:**
  - `../reviews/2026-11-28-cloud-ui-inventory.md` and its screenshots;
  - `lib/features/cloud/presentation/widgets/cloud_note_review.dart`;
  - `cloud_new_device_step.dart`;
  - `AgentActivationGroupLabel`;
  - the tag-limit and note-limit text uses.
- **Today's note dialog:**
  - two names for one thing: "Cloud note" vs "Incoming note", and "云端备注"
    vs "传入的笔记";
  - "Save resolution" / "保存处理结果";
  - "Combine versions" and "Show latest versions" buttons;
  - an editor cut off at the default window size.

### Contract

#### Note conflict

**On the Skill detail:**

- Status text: "This note was edited on two devices." /
  "备注在两台设备上都被修改了。"
- One primary button: "Choose note" / "选择备注".

**The dialog:**

- **Header title:** "Choose which note to keep" / "选择要保留的备注".
- **One section per version, in this order:**
  1. the synced version;
  2. the other device's version;
  3. this device's unsynced version, when there is one.

  Section titles:

  | Version | Title (EN / ZH) |
  | --- | --- |
  | written by a device whose name is known (1 or 2) | "From {device}" / "来自 {device}" |
  | device name not known | "Synced note" / "已同步的备注" |
  | this device's unsynced version | "On this device" / "这台设备上的" |

  - An empty version shows "No note" / "无备注".
  - Each section's trailing button is "Use this" / "使用此版本". It replaces
    the editor's text.
  - These are content controls, not state actions; record that in the
    Decision Log.
- **The editor section,** titled "Note to save" / "要保存的备注".
  - **It opens filled** with every distinct version joined by a blank line,
    which is today's "combine". So saving at once loses nothing.
  - Remove the "Combine versions" button.
- **Layout:**
  - at the default window size (800 × 600), the editor shows at least four
    lines, and it and the footer are fully visible without scrolling;
  - the version sections scroll above it.
  - If the existing dialog scaffold cannot do this, stop and ask.
- **Footer:**
  - secondary "Cancel" / "取消", which closes and changes nothing;
  - primary "Save note" / "保存备注".
- **A version changes while the dialog is open:**
  - update the version sections in place; the editor keeps the person's text;
  - show, above the editor: "This note changed on another device. The
    versions above are up to date, and your text is kept." /
    "此备注在另一台设备上有更改。上方已显示最新版本，你的文字会保留。"
  - "Save note" stays enabled.
  - Remove the "Show latest versions" button.
- **The conflict is resolved elsewhere while open:**
  - show "This conflict was resolved on another device." /
    "此冲突已在另一台设备上处理。";
  - the footer becomes one primary "Close" / "关闭".
- **Saving fails:**
  - show "Couldn't save the note. Check your connection and try again." /
    "未能保存备注，请检查网络后重试。";
  - "Save note" stays enabled; the text is kept.
- **The text is too long to sync:**
  - show "This note is too long to sync. Shorten it, then save." /
    "备注太长，无法同步。请缩短后再保存。";
  - "Save note" is disabled until it fits.

#### Note and tag limits elsewhere

- **Note too long, on the Skill detail:**
  - status "This note is too long to sync. Shorten it to sync it." /
    "备注太长，无法同步。缩短后即可同步。";
  - button "Edit note" / "编辑备注", unchanged.
- **Tag name too long:** "This tag name is too long to sync. Shorten it to sync
  it." / "标签名称太长，无法同步。缩短后即可同步。"
- **Tag vocabulary full:** unchanged.
- **No "KiB", "Unicode", or byte counts** appear anywhere in the UI.

#### The new-Device sheet

- **Header:**
  - title "Your synced Skills are ready" / "你同步的 Skill 已就绪";
  - subtitle "Choose which Agents can use them on this device." /
    "选择这台设备上哪些 Agent 可以使用它们。"
- **Each Skill section:**
  - title: the Skill's name;
  - under it: the Skill's description in one line, truncated, in the
    existing secondary text style;
  - when it has none, show nothing.
- **Each Agent row:**
  - the checkbox, then the Agent's icon and name, with the theme's small
    spacing between the checkbox and the icon;
  - no filesystem path;
  - for a project group, show the project's folder name only.
  - If `AgentActivationGroupLabel` cannot hide the path, add a parameter to
    it. Do not copy the widget.
- **At the default window size,** at least two Skill sections are visible
  before scrolling.
- **Footer:** unchanged, "Later" / "稍后" and "Activate selected Skills" /
  "启用所选 Skills".

### Acceptance

- **Widget tests:**
  - every note dialog state above, in EN and ZH;
  - that the editor opens with the combined text;
  - that a version change keeps the editor's text;
  - that cancel changes nothing;
  - the new-Device rows show no path;
  - the limit messages.
- **A search** of both ARB files finds no "KiB", "Unicode", "传入的笔记", or
  "保存处理结果".
- **Screenshots** (UI rule 8), in `branch-doc/screenshots/T44/`:
  - each note dialog state with two and with three versions;
  - the new-Device sheet with three Skills;
  - each limit message;
  - all in EN and ZH, light and dark, by extending T39's capture code.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code.

### Scope fence

- **In scope:**
  - the note review widget;
  - the new-Device step;
  - `AgentActivationGroupLabel`, for the path parameter only;
  - the ARB files and generated localizations;
  - tests and capture code.
- **Out of scope:**
  - attention actions, notices, and Settings (T43);
  - note sync behaviour in `skills_cloud`;
  - the 4 KiB and 64-character limits themselves.
- **Expected size:** about 6–10 files, 400–900 lines with tests and generated
  code.

### Stop and ask if

- Saving a note when the conflict has gone is needed, but the runtime cannot
  do it.
- The dialog scaffold cannot keep the editor and footer visible at 800 × 600.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
