#!/usr/bin/env bash
# no-yolo-mode.sh — PreToolUse hook for Edit/Write
# Blocks any file modification that introduces the --dangerously-skip-permissions flag
# or other "YOLO mode" patterns into settings or scripts.
# Exit 0 = allow, Exit 2 = block.

set -euo pipefail

FILE_PATH="${1:-}"
SCAN_MODE="file"
NEW_TEXT=""
if [[ -z "$FILE_PATH" ]]; then
    # shellcheck disable=SC1090,SC1091
    . "$(dirname "${BASH_SOURCE[0]}")/read-tool-input.sh"
    EVENT=""
    if [[ ! -t 0 ]]; then
        EVENT="$(cat 2>/dev/null || true)"
    fi
    FILE_PATH="$(read_tool_input_field file_path <<<"$EVENT")"
    # Hook-event mode judges the INCOMING text, not the pre-edit file: a
    # settings file that legitimately names the flag in its own deny list
    # must stay editable.
    SCAN_MODE="text"
    # Every incoming text: content, new_string, MultiEdit edits[] and NotebookEdit new_source.
    NEW_TEXT="$(read_tool_input_text <<<"$EVENT")"
    if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH="$(read_tool_input_field notebook_path <<<"$EVENT")"
    fi
fi
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only check text-like files
case "$FILE_PATH" in
    *.json|*.jsonc|*.ipynb|*.ps1|*.sh|*.bat|*.cmd|*.yaml|*.yml|*.toml|*.md|*.cs|*.ts|*.js)
        ;;
    *)
        exit 0 ;;
esac

if [[ "$SCAN_MODE" == "file" && ! -f "$FILE_PATH" ]]; then
    exit 0
fi
if [[ "$SCAN_MODE" == "text" && -z "$NEW_TEXT" ]]; then
    exit 0
fi

# Patterns indicating attempts to bypass permission gates
YOLO_PATTERNS=(
    'dangerously-skip-permissions'
    'dangerouslySkipPermissions'
    '--yolo\b'
    'claude_yolo'
    'CLAUDE_YOLO'
    'disable[_-]?permissions'
    'skipPermissions["]?[[:space:]]*[:=][[:space:]]*true'
    'bypass[_-]?safety'
)

for pattern in "${YOLO_PATTERNS[@]}"; do
    if [[ "$SCAN_MODE" == "text" ]]; then
        grep -Eiq -e "$pattern" <<<"$NEW_TEXT" || continue
    else
        grep -EiqI -e "$pattern" "$FILE_PATH" 2>/dev/null || continue
    fi
    echo "BLOCKED by no-yolo-mode: detected permission-bypass pattern in $FILE_PATH" >&2
    echo "Pattern matched: $pattern" >&2
    echo "" >&2
    echo "Permission gates exist to prevent destructive actions. The --dangerously-skip-permissions" >&2
    echo "flag bypasses all safety checks and is the single point of catastrophic failure for AI" >&2
    echo "coding tools (Check Point Research, CVE-2025-59536 context)." >&2
    echo "" >&2
    echo "If you genuinely need to enable this for a one-off, do it interactively in a terminal," >&2
    echo "not by committing it to a settings file." >&2
    exit 2
done

exit 0
