# model-fit

A Claude Code mod that shows the model and effort in use above the prompt, and suggests a better fit for the task at hand.

```
Model    opus-5-5 · high  → try sonnet · medium: routine single-file edit
```

`✓ fits` replaces the suggestion when it names the setting already in use. Switch with `/model` and `/effort`. After a switch the row shows the new setting from your next request on.

## How it suggests

After each turn, one Haiku call reads your last request (first 1,200 characters), up to three earlier ones, the current setting and what each turn did (read-only calls, edits and files, shell commands, failed calls, subagents spawned; a subagent's own calls are not counted). It answers with a model, an effort and a short reason. The default for building and review is Opus at medium effort; cheaper tiers are suggested for lookups and routine edits, higher effort for multi-file design, subtle bugs or repeated failures.

## Cost

One small Haiku request per finished turn (under 1k tokens in, a line out), billed like any other request. It does not hold up the turn.

## Install

Needs Claude Code v2.1.316 or later. At the prompt of a terminal session:

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install model-fit@agenticbase
```

From a shell:

```bash
claude plugin marketplace add DaMacDev/AgenticBase
claude plugin install model-fit@agenticbase
```

Desktop app: click **+** next to the prompt box, then **Plugins**, **Add marketplace**, enter `DaMacDev/AgenticBase`, then add model-fit.

Works beside `usage-meter`: each draws its rows in the same band.

## What it runs

Mod code, inside Claude Code, on your machine. After each turn it sends one Haiku request through Claude Code, on your account: your last request, including anything pasted into it (first 1,200 characters), up to three earlier ones (first 200 characters each), the current model and effort, and counts of what each turn did. It keeps your recent requests, the names of edited files, the setting and the suggestion in memory only; nothing is stored. It runs no command and writes no file.
