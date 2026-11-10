---
name: skilldeck
description: Use when the user wants an Agent to install, activate, update, organize, or remove Skills managed by SkillDeck.
---

# SkillDeck

Use the running SkillDeck App through its command-line client.

## Find the client

- macOS: `~/.skilldeck/bin/skilldeck`
- Windows: `%USERPROFILE%\.skilldeck\bin\skilldeck.exe`

If the binary is missing, ask the user to open SkillDeck once.
Never fall back to the npm `skills` CLI.

Below, `skilldeck` means that absolute binary path. Quote paths when needed.
Run `skilldeck help --json` for the full command catalog and flags.

## Execute and report

Always pass `--json` when parsing results. Before any write touching more than
one Skill, run the same command with `--dry-run` and review the selected set.
Read the result and exit code before deciding what to do next:

| Exit code | Meaning |
| --- | --- |
| 0 | All items succeeded or committed |
| 1 | Failed, including denied or expired approval |
| 2 | Usage error; consult help |
| 3 | Partial batch; report committed items, failures, and unattempted items |
| 4 | App unavailable or protocol mismatch |
| 5 | Waiting on the user in the App |
| 130 | Cancelled |

Removal, Personal Tag deletion, Source Replacement, and Source relink require
the user's approval in SkillDeck. Source relink reconnects adopted Skills using
read-only GitHub hints from the skills.sh lock; preview before applying.
Tell the user that a request is waiting in the App. If the result contains
`approvalPending`, retain its id and resume with
`skilldeck approvals wait <id> --json`. Never try to bypass approval.

For `actionRequired`, tell the user which screen to open using `details.screen`.
Do not retry blindly. Report `committedFinalizationPending` as committed work
awaiting recovery, and follow the App's recovery guidance.

## Examples

```sh
skilldeck list --all --json
skilldeck activate <refs> --agent <id> --json
skilldeck install <source> --skill <name> --agent <id> --json
skilldeck update --all --check --json
skilldeck remove <ref> --json
skilldeck source replace --source <prefix> --to <locator> --json
skilldeck source relink --from-skills-lock --dry-run --json
```
