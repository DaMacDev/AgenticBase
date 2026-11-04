# repo-review

A skill that reviews a whole repository and writes every real issue to a numbered report, `docs/repo-review-<date>.md`. It covers docs that no longer match the code, dead code, test gaps, broken check commands and the repo's own rules. Each finding has evidence (a file and line, or command output) and a short fix plan. Review mode changes no code.

A later run with `--fix` works through the open findings in order, ticks each one off in the report, and marks a finding that turned out wrong as void, with the reason.

## Install

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install repo-review@agenticbase
```

Then say "review this repo", or run `/repo-review:repo-review` (and `/repo-review:repo-review --fix` later).

## What it runs

A skill: instructions, not a program. Claude reads the repo, runs `git status`, `git log` and the repo's documented check commands, writes the report and commits it. Only reading, the report file, `git status --short` and `git log --oneline -5` are pre-approved; check commands, edits and commits ask for permission, since the repo under review may not be trusted. Fix mode edits code and commits each fix. Nothing is sent anywhere by the skill itself.
