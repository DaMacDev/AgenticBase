#!/usr/bin/env bash
# read-tool-input.sh — sourced helper, not a hook itself.
# Claude Code delivers the hook event as JSON on stdin; there is no
# ${TOOL_INPUT_*} substitution (code.claude.com/docs/en/hooks). Hook scripts
# keep their $1 form for direct/test invocation and call this when $1 is empty.
# shellcheck shell=bash

# _parse_retry <cmd...> — feeds the caller's $event to <cmd> on stdin and prints its output, up
# to 3 tries. On Windows a parse run now and then fails on a valid event: of several hooks fed
# the same event, one fails and the rest parse it. Invalid JSON fails all 3 and blocks.
_parse_retry() {
    local out _
    for _ in 1 2 3; do
        out="$(printf '%s' "$event" | "$@" 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    done
    return 1
}

# read_tool_input_field <field> — prints tool_input.<field> from the stdin
# event, or nothing if stdin is empty/a terminal/lacks the field.
# FAILS CLOSED: returns 2 (stderr says why) when the event can't be parsed
# (invalid JSON, or no jq and no working python). Every caller does
# `X="$(read_tool_input_field f)"` under `set -e`, so that status ends the hook
# with exit 2 = block. (An `exit` inside the helper would only end the subshell.)
read_tool_input_field() {
    local field="$1"
    if [[ -t 0 ]]; then
        return 0
    fi
    local event
    event="$(cat 2>/dev/null || true)"
    if [[ -z "$event" ]]; then
        return 0
    fi
    if command -v jq >/dev/null 2>&1; then
        # shellcheck disable=SC2016  # $f is a jq variable, not a shell expansion
        _parse_retry jq -r --arg f "$field" '.tool_input[$f] // empty' && return 0
        echo "BLOCKED: hook input is not valid JSON - failing closed" >&2
        return 2
    fi
    # Windows: "python3" may be the Store stub — probe before trusting.
    local py
    for py in python3 python py; do
        if command -v "$py" >/dev/null 2>&1 && "$py" -c "pass" >/dev/null 2>&1; then
            # The event goes in on stdin: an environment variable caps it at 32K characters on Windows.
            _parse_retry "$py" -c '
import json, sys
try:
    event = json.load(sys.stdin)
except Exception:
    sys.exit(3)
value = (event.get("tool_input") or {}).get(sys.argv[1], "")
if isinstance(value, str):
    sys.stdout.write(value)
' "$field" && return 0
            echo "BLOCKED: hook input is not valid JSON - failing closed" >&2
            return 2
        fi
    done
    echo "BLOCKED: hook cannot parse its input (no jq or python found) - failing closed. Install jq." >&2
    return 2
}

# read_tool_input_text — prints the text a Write/Edit/MultiEdit/NotebookEdit is about to put into
# a file (tool_input.content, .new_string, every .edits[].new_string, .new_source), one per line.
# Same stdin rules and fail-closed status as read_tool_input_field.
read_tool_input_text() {
    if [[ -t 0 ]]; then
        return 0
    fi
    local event
    event="$(cat 2>/dev/null || true)"
    if [[ -z "$event" ]]; then
        return 0
    fi
    if command -v jq >/dev/null 2>&1; then
        _parse_retry jq -r '.tool_input | [.content, .new_string, .new_source, ((.edits // []) | .[]? | .new_string)] | map(select(type == "string")) | .[]' && return 0
        echo "BLOCKED: hook input is not valid JSON - failing closed" >&2
        return 2
    fi
    local py
    for py in python3 python py; do
        if command -v "$py" >/dev/null 2>&1 && "$py" -c "pass" >/dev/null 2>&1; then
            _parse_retry "$py" -c '
import json, sys
try:
    event = json.load(sys.stdin)
except Exception:
    sys.exit(3)
ti = event.get("tool_input") or {}
parts = [ti.get("content"), ti.get("new_string"), ti.get("new_source")] + [e.get("new_string") for e in (ti.get("edits") or []) if isinstance(e, dict)]
sys.stdout.write("\n".join(p for p in parts if isinstance(p, str)))
' && return 0
            echo "BLOCKED: hook input is not valid JSON - failing closed" >&2
            return 2
        fi
    done
    echo "BLOCKED: hook cannot parse its input (no jq or python found) - failing closed. Install jq." >&2
    return 2
}
