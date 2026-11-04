---
name: repo-review
description: Review a whole repository and record every real issue — doc/status drift, dead code, rules violations, test gaps, broken verify commands — as a durable numbered report in docs/repo-review-<date>.md, each finding with evidence and a fix plan; a later --fix run works through the open findings. Use when the user says "review this repo", "go through the repo and record the issues", "what's wrong with this codebase", or "fix the identified issues from the repo review". Whole-repo scope — for the current diff use /code-review.
user-invocable: true
argument-hint: "[--fix [report-path]]"
allowed-tools: Read, Glob, Grep, Write(docs/repo-review-*.md), Edit(docs/repo-review-*.md), Bash(git status --short), Bash(git log --oneline -5)
---







Two sessions that compose: one reviews the repo and records each issue with a plan, a later
one fixes the recorded issues. This skill fixes the report location, the format and the fix pass.

Only reading, the report file, `git status --short` and `git log --oneline -5` are pre-approved. The repo's check
suite, fix-mode edits and commits go through the normal permission prompts: the repo under
review may not be trusted.

## Scope boundaries (reuse, don't duplicate)











- Current diff or branch → `/code-review`. This skill owns what that does not: the
  whole-repo review with a durable, actionable report.

## Review mode (default)






1. **Establish live state, never memory:** `git status --short && git log --oneline -5`,
   the status doc (README, `PROGRESS.md` or similar) and the repo's own rules
   (`CLAUDE.md`, `CONTRIBUTING.md`).
2. **Sweep in passes**, recording only verified findings (evidence = file:line or command
   output, not impressions):
   - **Docs vs reality** — status-doc claims vs code (listed-but-unbuilt features, dead
     links/paths, stale counts, frozen `## Status` blocks).




   - **Code health** — dead code (zero non-test importers), duplication against existing
     helpers, stale TODO/FIXME.
   - **Tests** — non-trivial logic with no runnable check, red or skipped tests
     (distinguish known machine-local noise from regressions).




   - **Rules compliance** with the repo's own rules — at minimum no committed secrets, a
     lockfile with pinned dependencies, and a status doc that matches the code.
   - **Verify commands** — run the repo's documented check suite; record failures.
3. **Write the report** to `docs/repo-review-YYYY-MM-DD.md` (format below) and commit it.
4. **Fix nothing.** Review mode is findings-only. Close by reporting counts by severity,
   the top findings, and the fix invocation: `/repo-review:repo-review --fix`.

## Report format

```markdown
# Repo review — {repo} — {YYYY-MM-DD}




Reviewed at commit {hash}

## Findings

- [ ] 1. [HIGH] {one-line issue}
  - Evidence: {file:line or command output}
  - Plan: {how to fix, 1–3 lines}
- [ ] 2. [MEDIUM] …
```

Severity: HIGH (broken/misleading now) · MEDIUM (costs future sessions) · LOW (polish).
Order findings by severity. The checkboxes are the fix pass's worklist — keep the
numbering stable once committed.

## Fix mode (`--fix`)

1. **Locate the report:** the explicit path argument, else the newest
   `docs/repo-review-*.md`. No report found → say so and offer a review run; never
   silently review instead.





2. **Work through unchecked findings in order**, under the repo's own rules (a failing
   test first per fix when they ask for it). Verify each fix, tick its checkbox in the
   report in the same change, and commit coherent units as you go.
3. **A finding that turns out wrong or obsolete** → tick it with `— VOID: {reason}`
   appended; deferred or dropped is never silent.




4. **Close out:** update the status doc if scope or status changed, and report
   fixed / void / remaining counts.

## Rules





- Reports are durable and committed in `docs/`, not kept in a scratch or plans folder.
- Review mode never modifies code, config, or tests — the report is the only artifact.
- Findings without evidence don't go in the report.
