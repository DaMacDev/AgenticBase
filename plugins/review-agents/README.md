# review-agents

Two read-only review agents for Claude Code:

- **reviewer** reviews a change before it merges: correctness, architecture, tests, UI and end-to-end test smells, performance, durability and doc comments. It tries to disprove each finding before reporting it, ranks what survives as WILL BREAK, COST or ROT, and ends with one verdict: `SHIP`, `SHIP WITH FIXES` or `DO NOT SHIP`.
- **security** reviews security and privacy: auth, credentials, server-side validation, personal data, redaction, and child safety where an app has minors. It reports each finding with severity, file and line, and a minimal fix.

## Install

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install review-agents@agenticbase
```

Then ask Claude to "review this branch with the reviewer agent", or mention `@review-agents:reviewer` or `@review-agents:security`.

## What it runs

Subagents with read-only tools only (Read, Grep, Glob). They read your code and report; they cannot edit files, run commands or reach the network. They ask for the Opus model. To use another model, copy the agent file into `~/.claude/agents/` and change its `model:` line there: a plugin update overwrites edits inside the plugin.
