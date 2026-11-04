#!/usr/bin/env bash
# warn-home-dir.sh -- SessionStart hook: warn when a session opens in the home directory.
#



# Sessions can start in the user's home folder because
# the desktop app lands there when no folder is picked. Nothing there is a
# project: transcripts and stray files pile into the user profile and no project
# rules or hooks load. A SessionStart hook cannot block or redirect a session --
# this is a loud nudge to reopen in a scratch folder or a real project folder.
#
# Read-only. Exit 0 always (a SessionStart hook must not block the session);
# emits hookSpecificOutput JSON on stdout only when cwd is the home directory.

set -euo pipefail

input="${1:-}"
if [ -z "$input" ] && [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
fi

home="${USERPROFILE:-}"
[ -n "$home" ] || exit 0

# Session dir: prefer the env Claude Code injects; fall back to the stdin cwd,
# which arrives with JSON-escaped backslashes -- the unescape is mandatory.
cwd="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$cwd" ]; then
  [ -n "$input" ] || exit 0
  # `|| true`: a SIGPIPE from head under pipefail must not turn the "exit 0 always" promise into a hook error.
  c="$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
  c="${c//\\\\/\\}"
  [ -n "$c" ] && cwd="$c"
fi
[ -n "$cwd" ] || exit 0

# Windows paths: compare case-insensitively, slash-agnostically, sans trailing separator.
norm() {
  local p="${1//\\//}"
  p="${p%/}"
  printf '%s' "${p,,}"
}
[ "$(norm "$cwd")" = "$(norm "$home")" ] || exit 0




directive="[!] This session started in the home directory ($home), not a project. Transcripts and stray files land in the user profile here, and no project rules or hooks load. Tell the user to close this session and reopen Claude Code in a scratch folder or the project folder they actually mean to work in."

esc="$(printf '%s' "$directive" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
exit 0
