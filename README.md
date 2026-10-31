# AgenticBase

Claude Code plugins by DaMacDev: a usage meter for your prompt and a set of safety hooks. MIT licensed. Not affiliated with or endorsed by Anthropic.

## Install

Add the marketplace once, then install what you want:

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install usage-meter@agenticbase
/plugin install guard-hooks@agenticbase
```

## Plugins

| Plugin | What it does | What it runs | Needs |
| --- | --- | --- | --- |
| [usage-meter](plugins/usage-meter) | Live gauges above the prompt for context fill, the 5-hour and weekly plan limits (with pace and reset time), plus zero-token /clear vs /compact hints. | Mod code inside Claude Code. Reads usage figures Claude Code already has and keeps the last-seen limits in the plugin store. No network, no commands. | Claude Code v2.1.287 or later |
| [guard-hooks](plugins/guard-hooks) | Four safety hooks: block destructive shell commands, hardcoded secrets and permission-bypass flags, and check WebFetch URLs against an allowlist. | Bash scripts before Edit, Write, Bash, PowerShell and WebFetch calls. Reads the tool call, writes one audit log for WebFetch (host only), sends nothing. | Claude Code, bash (without it the hooks give no protection), and jq or Python 3 (the hooks block calls without them) |

## Compatibility

- **Claude Code:** both plugins. Mods need Claude Code v2.1.287 or later (the desktop app: v2.1.286 or later). Hooks need a version with plugin hooks and `bash`: without bash (or with a hook shell that is not POSIX) they do not run and give no protection.
- **Other tools:** mods use the Claude Code mods API and run only in Claude Code. The guard hooks are plain scripts that read the hook event as JSON on stdin and block with exit code 2. The vendors document support for this format, but AgenticBase has not tested it there:
  - GitHub Copilot applies Claude's matcher rules to hooks configured with the PascalCase `PreToolUse` event, as used in Claude Code plugins ([hooks configuration](https://docs.github.com/en/copilot/reference/hooks-configuration)).
  - Codex runs plugin hooks and sets `CLAUDE_PLUGIN_ROOT` for compatibility with existing plugin hooks ([Codex hooks](https://developers.openai.com/codex/hooks)).
  - Cursor loads hooks from third-party tools like Claude Code, and exit code 2 blocks the action there too ([Cursor hooks](https://cursor.com/docs/agent/hooks)).

## Security

Hooks and mods run code on your machine with your permissions. Read the source before you install; it is short.

- **guard-hooks** runs bash scripts before Edit, Write, MultiEdit, NotebookEdit, Bash, PowerShell and WebFetch calls. They read the tool call (command, URL or text about to be written) from stdin and decide. They need `bash`; without it they do not run and give no protection. They need `jq` or Python 3 to read the event, and block the call without them. They send nothing over the network. The only file they write is the WebFetch audit log in your home folder (scheme and host of each URL; no path, query string or credentials).
- **usage-meter** runs mod code inside Claude Code. It reads the usage figures Claude Code provides, prompt times, the names of edit tools and the text of Bash commands (to spot `git commit` and `git push`). It keeps the last-seen limits in the plugin store. It makes no network call and runs no command.

Report a vulnerability as described in [SECURITY.md](SECURITY.md).

## Contributing

Issues are welcome. Pull requests are by invitation. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT, see [LICENSE](LICENSE). Credits and third-party licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
