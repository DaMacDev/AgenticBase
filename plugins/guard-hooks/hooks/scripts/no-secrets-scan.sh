#!/usr/bin/env bash
# no-secrets-scan.sh — PreToolUse hook for Edit/Write
# Blocks edits that would introduce hardcoded secrets: as a hook it scans the text being written
# (Write content, Edit/MultiEdit new_string), not the file as it is now. `no-secrets-scan.sh <file>`
# scans an existing file.
# Exit 0 = allow, Exit 2 = block (Claude Code shows the stderr to the user)

set -euo pipefail

FILE_PATH="${1:-}"
TEXT=""
if [[ -z "$FILE_PATH" ]]; then
    # shellcheck disable=SC1090,SC1091
    . "$(dirname "${BASH_SOURCE[0]}")/read-tool-input.sh"
    EVENT="$(cat 2>/dev/null || true)"
    FILE_PATH="$(read_tool_input_field file_path <<<"$EVENT")"
    TEXT="$(read_tool_input_text <<<"$EVENT")"
    [[ -n "$TEXT" ]] || exit 0  # nothing being written
elif [[ ! -f "$FILE_PATH" ]]; then
    exit 0  # nothing to check
fi

# Skip non-source files
case "$FILE_PATH" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.tar|*.gz)
        exit 0 ;;
esac

# Patterns considered likely secrets (case-insensitive)
PATTERNS=(
    'password[[:space:]]*=[[:space:]]*"[^"]{4,}"'
    'passwd[[:space:]]*=[[:space:]]*"[^"]{4,}"'
    'api[_-]?key[[:space:]]*=[[:space:]]*"[^"]{16,}"'
    'secret[[:space:]]*=[[:space:]]*"[^"]{8,}"'
    'token[[:space:]]*=[[:space:]]*"[^"]{20,}"'
    'bearer [a-zA-Z0-9_\-]{20,}'
    'AKIA[0-9A-Z]{16}'  # AWS access key
    'ghp_[A-Za-z0-9]{36}'  # GitHub personal access token
    'sk-[A-Za-z0-9]{20,}'  # OpenAI/Anthropic-style key
)

for pattern in "${PATTERNS[@]}"; do
    if { if [[ -n "$TEXT" ]]; then grep -EiqI "$pattern" <<<"$TEXT"; else grep -EiqI "$pattern" "$FILE_PATH"; fi; } 2>/dev/null; then
        echo "BLOCKED: Possible hardcoded secret detected in $FILE_PATH" >&2
        echo "Pattern matched: $pattern" >&2
        echo "If this is a false positive, refactor to use environment variables or user-secrets." >&2
        echo "If this is a real secret, rotate it immediately and use the appropriate secret store." >&2
        exit 2
    fi
done

exit 0
