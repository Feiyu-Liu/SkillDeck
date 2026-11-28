# ExecPlan: T45 T43 fixes: one same-name sentence, a true conflict subtitle, clean T41 captures

Rework from `../reviews/2026-11-28-t41-t44-review.md`: F-3, F-4, and the F-1
recapture. App only. Simplicity rules **and UI rules**: see
`../execplan-template.md`. **Use only the text below.**

## Set by the planner

### Goal

- The same-name state says its sentence once.
- The conflict dialog's subtitle is true about what the App's history shows.
- The T41 native sign-in evidence shows no personal data.

### Context

- **Read first:** the review's F-1, F-3, and F-4; T43 as delivered;
  `cloud_attention_actions.dart`; `workspace_history_reader.dart`
  (`readPublishedHistory`); `candidate_conflict_preparation.dart`.
- **F-3:** "A synced Skill has the same name as this Skill." shows in the
  status line and again above the buttons (`cloud_attention_actions.dart`,
  about lines 93–97).
- **F-4:** T43 Fact 4 was shown for Git ancestry. The App's history list is
  read from operation records, so the version not kept may not be listed.
- **F-1:** the two T41 native captures were removed from the branch because the
  browser's autofill menu showed a personal address. The maintainer decided
  not to rewrite history.

### Contract

#### 1. Same-name state (F-3)

- Delete the separate `Text` above the buttons. Only the status line says
  "A synced Skill has the same name as this Skill." /
  "有一个已同步的 Skill 与此 Skill 同名。"
- If its ARB key is then unused, delete it from both ARB files.

#### 2. Conflict dialog subtitle (F-4)

- **First, test what the App shows.** Add a test that:
  1. creates a sync merge conflict;
  2. resolves it with "Keep this device's version";
  3. publishes;
  4. reads the published history through the App's history reader.

  Repeat with "Keep the other device's version".
- **Then set the subtitle while choosing:**

  | Test result | Subtitle (EN / ZH) |
  | --- | --- |
  | The version not kept is listed in both cases | unchanged: "The same files were changed on two devices. Choose which version to keep. The other version stays in this Skill's history." / "两台设备修改了相同的文件。请选择要保留的版本，另一个版本会留在此 Skill 的历史记录中。" |
  | It is missing in either case | "The same files were changed on two devices. Choose which version to keep." / "两台设备修改了相同的文件。请选择要保留的版本。" |

- **If it is missing:** write
  `../follow-ups/conflict-history-visibility.md` in the style of
  `../follow-ups/source-replacement-history.md`. It records what the history
  list shows after each choice, with the test name.
- Correct T43's Decision Log entry for Fact 4 with the test name and result.
- Add the test names for Facts 2, 3, and 5 where tests exist (review F-5).

#### 3. T41 native captures (F-1)

- Recapture `screenshots/T41/native-staging-en.png` and
  `native-staging-zh.png` against staging.
- Before each capture, dismiss the browser's autofill menu, or use a browser
  profile with no saved addresses.
- **Before committing, look at each image.** It must show no email address,
  name, or saved credential. If it does, do not commit it.

### Acceptance

- Widget test: the same-name state renders its sentence exactly once, in EN
  and ZH.
- The history test above, both choices.
- Screenshots (UI rule 8):
  - `screenshots/T45/` for the same-name state and the conflict dialog while
    choosing, in EN and ZH, light and dark, by T39's capture code;
  - the two T41 native captures.
- Gates: the App gates from `CLAUDE.md`, each with its own exit code.

### Scope fence

- **In scope:** `cloud_attention_actions.dart`, the conflict dialog subtitle,
  the ARB files and generated localizations, the new test, capture code, the
  follow-up file, the two T41 images.
- **Out of scope:** changing what history records, and any `skills_workspace`
  behaviour. Showing the other version in history is a follow-up, not this
  card.
- **Expected size:** about 4–6 files, 100–250 lines with tests.

### Stop and ask if

- The history test cannot be written without changing `skills_workspace`.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
