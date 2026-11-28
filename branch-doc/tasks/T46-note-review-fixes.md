# ExecPlan: T46 T44 fixes: distinct note titles, no dead buttons, theme spacing

Rework from `../reviews/2026-11-28-t41-t44-review.md`: F-6, F-7, F-9, and
F-10. App only. Can run in parallel with T45; if both touch the ARB files,
rebase and regenerate. Simplicity rules **and UI rules**: see
`../execplan-template.md`. **Use only the text below.**

## Set by the planner

### Goal

- No two version sections in the note dialog have the same title.
- No button stays active when it can do nothing useful.
- The new-Device rows use theme spacing.

### Context

- **Read first:** the review's T44 notes; T44 as delivered;
  `cloud_note_review.dart`; `cloud_new_device_step.dart`.
- **F-6:** when no device name is known, the synced version and the other
  device's version are both titled "Synced note" / "已同步的备注".
- **F-7:** after the conflict is resolved elsewhere, each "Use this" button is
  still enabled and changes hidden text (`cloud_note_review.dart`, about lines
  222–225).
- **F-9:** no test or capture gives a device name, so "From {device}" is
  untested.
- **F-10:** the checkbox-to-icon gap is `SizedBox(width: 6)`
  (`cloud_new_device_step.dart`, about line 198).

### Contract

#### Section titles (F-6)

This table replaces T44's section-title table. The order of sections is
unchanged.

| Version | Device name known | Title (EN / ZH) |
| --- | --- | --- |
| the synced version | yes | "From {device}" / "来自 {device}" |
| the synced version | no | "Synced note" / "已同步的备注" |
| the other device's version | yes | "From {device}" / "来自 {device}" |
| the other device's version | no | "From another device" / "来自另一台设备" |
| this device's unsynced version | — | "On this device" / "这台设备上的" |

- If both the synced and the other version name the same device, the synced
  section uses "Synced note" / "已同步的备注", so the titles still differ.

#### Resolved elsewhere (F-7)

- When "This conflict was resolved on another device." shows, hide every
  "Use this" button. The version sections stay visible, read only.

#### Spacing (F-10)

- Replace `SizedBox(width: 6)` with the theme's small spacing token. Use
  `AppSpacing.sm`; if that is wider than 8 px, use `AppSpacing.xs`. Record
  which in the Decision Log.

### Acceptance

- **Widget tests, in EN and ZH:**
  - every row of the title table, including a named device (F-9);
  - the same-device case;
  - no "Use this" button after the conflict is resolved elsewhere.
- **Screenshots** (UI rule 8), in `screenshots/T46/`, EN and ZH, light and
  dark, by T39's capture code:
  - the dialog with a named device;
  - the dialog with an unknown device, showing "From another device";
  - the resolved-elsewhere state;
  - one new-Device row.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code.

### Scope fence

- **In scope:** `cloud_note_review.dart`, `cloud_new_device_step.dart`, the
  ARB files and generated localizations, tests, capture code.
- **Out of scope:** note sync behaviour; the dialog layout (F-8 stays a
  follow-up).
- **Expected size:** about 4–6 files, 100–250 lines with tests.

### Stop and ask if

- The dialog does not know which device wrote each version.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
