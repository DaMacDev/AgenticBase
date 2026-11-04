# AgenticBase

Claude Code plugins by DaMacDev: mods, hooks, skills and agents, each installed on its own. MIT licensed. Not affiliated with or endorsed by Anthropic.

## Install

Add the marketplace once, then install what you want:

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install usage-meter@agenticbase
/plugin install guard-hooks@agenticbase
/plugin install model-fit@agenticbase
/plugin install web-qa@agenticbase
/plugin install review-agents@agenticbase
/plugin install repo-review@agenticbase
```

## Plugins

| Plugin | What it does | What it runs | Needs |
| --- | --- | --- | --- |
| [usage-meter](plugins/usage-meter) | Live gauges above the prompt for context fill, the 5-hour and weekly plan limits (with pace and reset time), plus zero-token /clear vs /compact hints. | Mod code inside Claude Code. Reads usage figures Claude Code already has and keeps the last-seen limits in the plugin store. No network, no commands. | Claude Code v2.1.287 or later |
| [guard-hooks](plugins/guard-hooks) | Six safety hooks: block destructive shell commands, hardcoded secrets, permission-bypass flags and commits that do not type-check, check WebFetch URLs against an allowlist, and warn when a session starts in the home folder. | Bash scripts at session start and before Edit, Write, Bash, PowerShell and WebFetch calls. Reads the tool call, runs the project's own `typecheck` script before a `git commit`, writes one audit log for WebFetch (host only), sends nothing. | Claude Code, bash (without it the hooks give no protection), and jq or Python 3 (the hooks block calls without them) |
| [model-fit](plugins/model-fit) | Shows the model and effort in use above the prompt, with a suggested model and effort for the task at hand. | Mod code inside Claude Code. After each turn, one small Haiku request through Claude Code with your recent requests and a count of what the turn did. No commands, no files. | Claude Code v2.1.316 or later |
| [web-qa](plugins/web-qa) | Three skills for web UI testing: set up Playwright with a phone and desktop matrix and accessibility checks, fuzz forms with adversarial input, and test a flaky or offline network. | Skills (instructions). Claude writes test files and config into your project and runs your test commands; the setup skill installs npm dev packages. | Claude Code; a Node web project for the tests |
| [review-agents](plugins/review-agents) | Two read-only review agents: a pre-merge code reviewer and a security and privacy reviewer. | Subagents with read-only tools (Read, Grep, Glob). They report findings and change nothing. | Claude Code |
| [repo-review](plugins/repo-review) | Review a whole repository and record every real issue as a numbered report with evidence and a fix plan; a later run works through the open findings. | A skill (instructions). Claude reads the repo, runs its tests and writes one report file under `docs/`; the fix run edits code. | Claude Code |

## Compatibility

- **Claude Code:** all plugins. Mods need Claude Code v2.1.287 or later (the desktop app: v2.1.286 or later); model-fit needs v2.1.316 or later. Hooks need a version with plugin hooks and `bash`: without bash (or with a hook shell that is not POSIX) they do not run and give no protection.
- **Skills and agents** (web-qa, review-agents, repo-review) are Markdown instructions. They follow the Agent Skills and subagent formats of Claude Code; other tools that read those formats may run them, untested.
- **Other tools:** mods use the Claude Code mods API and run only in Claude Code. The guard hooks are plain scripts that read the hook event as JSON on stdin and block with exit code 2. The vendors document support for this format, but AgenticBase has not tested it there:
  - GitHub Copilot applies Claude's matcher rules to hooks configured with the PascalCase `PreToolUse` event, as used in Claude Code plugins ([hooks configuration](https://docs.github.com/en/copilot/reference/hooks-configuration)).
  - Codex runs plugin hooks and sets `CLAUDE_PLUGIN_ROOT` for compatibility with existing plugin hooks ([Codex hooks](https://developers.openai.com/codex/hooks)).
  - Cursor loads hooks from third-party tools like Claude Code, and exit code 2 blocks the action there too ([Cursor hooks](https://cursor.com/docs/agent/hooks)).

## Security

Hooks and mods run code on your machine with your permissions. Read the source before you install; it is short.

- **guard-hooks** runs bash scripts at session start and before Edit, Write, MultiEdit, NotebookEdit, Bash, PowerShell and WebFetch calls. They read the tool call (command, URL or text about to be written) from stdin and decide. They need `bash`; without it they do not run and give no protection. They need `jq` or Python 3 to read the event, and block the call without them. Before a `git commit` they run your project's own `typecheck` npm script, when it has one; that happens before you approve the commit, even if you then deny it. The scripts send nothing over the network (your project's own typecheck script may). The only file they write is the WebFetch audit log in your home folder (scheme and host of each URL; no path, query string or credentials).
- **usage-meter** runs mod code inside Claude Code. It reads the usage figures Claude Code provides, prompt times, the names of edit tools and the text of Bash commands (to spot `git commit` and `git push`). It keeps the last-seen limits in the plugin store. It makes no network call and runs no command.
- **model-fit** runs mod code inside Claude Code. After each turn it sends one small Haiku request through Claude Code, on your account: the text of your last request, including anything pasted into it (first 1,200 characters) and of up to three earlier ones (first 200 characters each), the model and effort in use, and counts of what each of those turns did (reads, edits, files edited, commands, failed calls, subagents). It keeps your recent requests, the names of edited files, the setting and the suggestion in memory only; nothing is stored. It runs no command and writes no file.
- **web-qa** and **repo-review** are skills: instructions Claude follows. While one is active, a few tools are pre-approved and skip the permission prompt. web-qa: reads, writes to the fixture, Playwright, Lighthouse and ESLint config files and `tests/e2e/`, `npm install --save-dev --save-exact`, `npx playwright install` (on Linux `--with-deps` installs system libraries with sudo) and `npm run lint`. repo-review: reads, its own `docs/repo-review-*.md` report, `git status --short` and `git log --oneline -5`; the repo's check commands, fix-mode edits and commits ask first.
- **review-agents** are subagents limited to Read, Grep and Glob: they cannot edit files, run commands or reach the network.

Report a vulnerability as described in [SECURITY.md](SECURITY.md).

## Contributing

Issues are welcome. Pull requests are by invitation. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT, see [LICENSE](LICENSE). Credits and third-party licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
