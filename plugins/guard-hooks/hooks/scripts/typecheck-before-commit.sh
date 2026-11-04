#!/usr/bin/env bash
# typecheck-before-commit.sh — PreToolUse hook for Bash commands.
# Blocks a `git commit` in a TS project whose types don't compile, because the
# test runner (vitest/esbuild) strips types and never runs `tsc` — a green test
# run can hide strict-tsc errors. Exit 0 = allow, Exit 2 = block.



# Greps the command for `git commit` and runs the project's own
# `typecheck` npm script; only fires when `scripts.typecheck` exists, so non-TS
# projects and projects without a typecheck gate are untouched. Fails open when
# npm is missing or the typecheck outlasts the hook timeout.

set -euo pipefail

CMD="${1:-}"
if [[ -z "$CMD" ]]; then
    # shellcheck disable=SC1090,SC1091
    . "$(dirname "${BASH_SOURCE[0]}")/read-tool-input.sh"
    CMD="$(read_tool_input_field command)"
fi
if [[ -z "$CMD" ]]; then
    exit 0
fi

# Only care about `git commit` (not commit --help, log, etc.)
if ! grep -Eq '(^|[;&|(][[:space:]]*)git[[:space:]]+commit' <<<"$CMD"; then
    exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PKG="$PROJECT_DIR/package.json"
[[ -f "$PKG" ]] || exit 0

if ! command -v npm >/dev/null 2>&1; then
    exit 0  # can't typecheck without npm; don't block
fi

# Only gate projects that define `scripts.typecheck` (npm implies node), not any "typecheck" key.
if ! node -e 'process.exit(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).scripts?.typecheck ? 0 : 1)' "$PKG" 2>/dev/null; then
    exit 0
fi

# Output stays in memory: no temp file to leak, race or leave behind on a timeout.
if ! out="$(cd "$PROJECT_DIR" && npm run --silent typecheck 2>&1)"; then
    echo "BLOCKED: \`git commit\` in a TypeScript project that does not type-check." >&2
    echo "A passing test run does NOT type-check (vitest/esbuild strips types)." >&2



    echo "Fix the type errors below, then commit." >&2
    echo "--- npm run typecheck ---" >&2
    printf '%s\n' "$out" | tail -30 >&2
    exit 2
fi
exit 0
