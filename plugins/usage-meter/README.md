# usage-meter

A Claude Code mod that keeps three live gauges above your prompt, so you can tell at a glance whether to keep going, `/compact` or `/clear`.

```
Context  ███████░░░░░░░ 136k/200k 68%  · auto-compact at 83%
5h       █████░░│░░░░░░  41%  time 60%  ✓ under pace   resets 2h00m
Week     ███░░░░░░│░░░░  22%  time 57%  ✓ under pace   resets Tue 14:00
💡 Context high, mid-task → /compact soon
```

Works in the terminal (`claude`) and in the desktop app's **Code** tab.

## What it shows

| Row | Meaning |
| --- | --- |
| **Context** | How full the conversation's context window is. Green < 50%, yellow ≥ 50%, red ≥ 75%. Also shows where auto-compact will fire. |
| **5h** | Your plan's 5-hour limit. The `│` marker is how much of the 5 hours has passed: if the bar is past the marker you are using faster than the window allows. |
| **Week** | The same for the 7-day limit. |
| **💡** | A hint, only when useful (see below). |

Pace verdicts: `✓ under pace`, `▲ ahead of pace, out ~1h20m` or `out ~Fri 08:00` (when you hit 100% at this rate, before the reset), `✖ limit reached`.

Limit bars go yellow past 70% or when ahead of pace, red past 90%. Crossing 90% on a limit raises one toast per window.

## The /clear vs /compact hints

Plain rules, no AI involved:

- **`/compact`**: context ≥ 75% and you're mid-task (files edited since the last commit). Keeps a summary so you can continue.
- **`/clear`**: context ≥ 30% and the task looks done (a `git commit`/`git push` within 20 min, no edits since).
- **`/clear`**: context ≥ 30% and you've been idle 30 min+: the prompt cache has expired, so the next turn re-reads the whole context at full price.
- **`/compact` or `/clear`**: context ≥ 75% in any other case.
- **`/clear` or `/compact`**: the 5h limit is tight and context ≥ 40%: a smaller context makes every later turn cheaper.

Reminder: `/clear` starts fresh (the old conversation stays available via `/resume`); `/compact` replaces history with a summary and continues. Neither gives back limit usage already spent: they make *future* turns cheaper.

## Cost

Zero tokens. The mod only reads figures Claude Code already has and never calls a model or adds to the prompt.

## Notes

- Limits only appear on a Claude subscription (Pro / Max). With an API key there are no limit windows; the context row still works.
- Limit figures arrive with each reply. Before the first reply of a new session the last-seen figures are shown dimmed, marked *last seen*.
- The band can be collapsed with its `[-]` control.

## Install

Needs Claude Code v2.1.287 or later (the desktop app: v2.1.286 or later). At the prompt of a terminal session:

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install usage-meter@agenticbase
```

From a shell:

```bash
claude plugin marketplace add DaMacDev/AgenticBase
claude plugin install usage-meter@agenticbase
```

Desktop app: click **+** next to the prompt box, then **Plugins**, **Add marketplace**, enter `DaMacDev/AgenticBase`, then add usage-meter.

## What it runs

Mod code, inside Claude Code, on your machine. It reads only the usage figures Claude Code already has (context size, plan limits, session activity), and keeps the last-seen limits in the plugin store that Claude Code provides. It makes no network call, runs no command and writes no file itself.

## Develop

```bash
claude plugin validate --strict plugins/usage-meter
claude plugin test plugins/usage-meter
```
