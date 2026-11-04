# guard-hooks

Six safety hooks for Claude Code. Five check each tool call before it runs and block it with exit code 2 when it looks unsafe; one warns at session start:

- **block-destructive** stops destructive Bash and PowerShell commands such as recursive deletes of the filesystem root, force pushes, `git reset --hard`, piping a download into a shell, and killing processes by name.
- **no-secrets-scan** stops edits that write a hardcoded password, API key or token.
- **no-yolo-mode** stops edits that add flags or settings which switch off Claude Code's permission checks.
- **sandbox-webfetch** allows WebFetch only for HTTPS URLs without credentials or long encoded query strings, asks before any host that is not on its allowlist, and caps fetches per hour.
- **typecheck-before-commit** stops a `git commit` in a project whose `package.json` has a `typecheck` script when that script fails. Test runners like Vitest strip types, so green tests can hide type errors.
- **warn-home-dir** tells Claude when a session starts in your home folder instead of a project (Windows only; it reads `USERPROFILE`).

## Install

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install guard-hooks@agenticbase
```

## What it runs

Bash scripts, on your machine, at session start and before Edit, Write, MultiEdit, NotebookEdit, Bash, PowerShell and WebFetch calls. They read the tool call from stdin, and the scripts send nothing over the network (your project's own typecheck script may). typecheck-before-commit runs your project's own `npm run typecheck` (with its npm pre and post scripts) before each `git commit` Claude proposes, for up to two minutes. Hooks run before Claude Code asks you to approve the call, so the typecheck runs even if you then deny the commit: don't install guard-hooks if you open repositories you don't trust. sandbox-webfetch appends one line per URL (time, scheme and host; no path, query string or credentials) to `~/.claude/harness/audit/audit-<project folder>.log`. The hooks need `bash`: without bash (or with a hook shell that is not POSIX) they do not run and give no protection. They also need `jq` or Python 3 to read the event; without those they block the call (fail closed).

## Limits

These hooks are speed bumps, not a sandbox. A determined command can get around the pattern checks. typecheck-before-commit lets the commit through when npm is missing or the typecheck takes longer than two minutes. Edit the pattern lists in `hooks/scripts/` to fit your needs.
