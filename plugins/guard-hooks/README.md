# guard-hooks

Four safety hooks for Claude Code. They check each tool call before it runs and block it with exit code 2 when it looks unsafe:

- **block-destructive** stops destructive Bash and PowerShell commands such as recursive deletes of the filesystem root, force pushes, `git reset --hard`, piping a download into a shell, and killing processes by name.
- **no-secrets-scan** stops edits that write a hardcoded password, API key or token.
- **no-yolo-mode** stops edits that add flags or settings which switch off Claude Code's permission checks.
- **sandbox-webfetch** allows WebFetch only for HTTPS URLs without credentials or long encoded query strings, asks before any host that is not on its allowlist, and caps fetches per hour.

## Install

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install guard-hooks@agenticbase
```

## What it runs

Bash scripts, on your machine, before Edit, Write, MultiEdit, NotebookEdit, Bash, PowerShell and WebFetch calls. They read the tool call from stdin and send nothing over the network. sandbox-webfetch appends one line per URL (time, scheme and host; no path, query string or credentials) to `~/.claude/harness/audit/audit-<project folder>.log`. The hooks need `bash`: without bash (or with a hook shell that is not POSIX) they do not run and give no protection. They also need `jq` or Python 3 to read the event; without those they block the call (fail closed).

## Limits

These hooks are speed bumps, not a sandbox. A determined command can get around the pattern checks. Edit the pattern lists in `hooks/scripts/` to fit your needs.
