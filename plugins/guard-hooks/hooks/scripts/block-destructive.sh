#!/usr/bin/env bash
# block-destructive.sh — PreToolUse hook for Bash and PowerShell commands
# Blocks known-destructive commands. Exit 0 = allow, Exit 2 = block.
# Both tools carry the command in tool_input.command, so one script guards both.

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

# Patterns that should never auto-run
DENY_PATTERNS=(
    'rm[[:space:]]+-rf?[[:space:]]+/'         # rm -rf /
    'rm[[:space:]]+-rf?[[:space:]]+~'         # rm -rf ~
    'rm[[:space:]]+-rf?[[:space:]]+\*'        # rm -rf *
    'git[[:space:]]+push[[:space:]]+.*--force' # force push
    'git[[:space:]]+reset[[:space:]]+--hard'   # hard reset
    'git[[:space:]]+clean[[:space:]]+-[a-z]*f' # git clean -f
    ':(){ :|:& };:'                            # fork bomb
    'curl[[:space:]]+.*\|[[:space:]]*sh'       # curl | sh
    'wget[[:space:]]+.*\|[[:space:]]*sh'       # wget | sh
    'sudo[[:space:]]+rm'                       # sudo rm
    'mkfs\.'                                   # filesystem format
    'dd[[:space:]]+.*of=/dev/'                 # dd to device
    '>/dev/sd[a-z]'                            # writing to block device
)

for pattern in "${DENY_PATTERNS[@]}"; do
    if grep -Eq "$pattern" <<<"$CMD"; then
        echo "BLOCKED: Destructive command pattern detected." >&2
        echo "Command: $CMD" >&2
        echo "Pattern matched: $pattern" >&2
        echo "If you really need this, run it manually outside Claude Code." >&2
        exit 2
    fi
done

# PowerShell deletes are judged on TARGET, not verb. `Remove-Item -Recurse -Force
# bin, obj` is everyday work and must keep running; the same command aimed at a
# profile or system root must not.





# PowerShell is case-insensitive, so these match case-insensitively.
PS_DELETE_VERB='Remove-Item|\[(System\.)?IO\.Directory\]::Delete|(^|[[:space:];|(])(rd|rmdir)[[:space:]]+/s'
# shellcheck disable=SC2016  # single quotes deliberate: \$env:/\$HOME are regex literals, not expansions



PS_PROTECTED_ROOT='\$env:(USERPROFILE|LOCALAPPDATA|APPDATA|ProgramFiles|ProgramData|SystemRoot|windir)|\$HOME|C:\\Users|C:\\Windows|C:\\Program Files|\.claude|WindowsApps'
# Recursive/bulk intent: -Recurse, cmd-style /s, a wildcard, or Directory::Delete's
# recursive $true. A single named file under the profile stays allowed.
# shellcheck disable=SC2016  # single quotes deliberate: \$true is a regex literal, not an expansion
PS_RECURSIVE='-Recurse|/s([[:space:]]|$)|\*|,[[:space:]]*\$true'

# `--` is required: PS_RECURSIVE starts with "-Recurse", which grep would otherwise
# parse as flags (including -r), silently recursing the cwd and matching anything.
if grep -Eqi -- "$PS_DELETE_VERB" <<<"$CMD" &&
    grep -Eqi -- "$PS_PROTECTED_ROOT" <<<"$CMD" &&
    grep -Eqi -- "$PS_RECURSIVE" <<<"$CMD"; then
    echo "BLOCKED: recursive delete aimed at a protected profile/system path." >&2
    echo "Command: $CMD" >&2



    echo "Protected roots: user profile, Windows, Program Files, .claude, WindowsApps." >&2
    echo "Delete a specific file, scope the delete to the project, or run it manually." >&2
    exit 2
fi

# Hook wiring: a shell command that rewrites Claude Code settings, the harness hook
# folder or the plugin-cache hook folder can switch off every guard (a prompt-injection
# path). Read allowlist per command segment: a segment naming a protected target
# must start with a read verb (or git/gh: commit messages mention these paths) and
# have no output redirect onto the target. Everything else touching a target is blocked.
# Speed bump: `cd .claude && echo x > settings.json` is not seen (relative target).
HOOK_TARGET='\.claude[/\]+(settings(\.local)?\.json|harness[/\]+hooks|plugins[/\][^[:space:]"'"'"']*hooks)'
HOOK_READ_VERB='^[[:space:](]*(cat|type|less|head|tail|grep|rg|jq|Get-Content|gc|Select-String|ls|dir|Get-ChildItem|Test-Path|diff|code|git|gh|wc|stat)([[:space:]]|$)'
# wc and stat joined the read verbs; nothing looser does: copy-out, path assignments and
# `sed -n` all had write variants (flags hidden by quotes, braces, $IFS, `~`/HOME expansion).
# Use `head -n M FILE | tail -n +N` for a line range. A substitution runs code inside a read.
hook_seg_reads() {
    # shellcheck disable=SC2016  # single quotes deliberate: $( and ` are literal substitution openers
    grep -Fq -e '$(' -e '`' -e '<(' -e '>(' <<<"$1" && return 1
    grep -Eqi -- "$HOOK_READ_VERB" <<<"$1"
}
while IFS= read -r seg; do
    grep -Eqi -- "$HOOK_TARGET" <<<"$seg" || continue
    if ! hook_seg_reads "$seg" ||
        grep -Eqi -- ">[^>]*$HOOK_TARGET" <<<"$(tr -d "\"'" <<<"$seg")"; then
        echo "BLOCKED: shell write to Claude Code settings or hook folders." >&2
        echo "Command: $CMD" >&2
        echo "Edit these files manually outside Claude Code." >&2
        exit 2
    fi
done < <(printf '%s\n' "$CMD" | tr ';|&' '\n')

# Kills by image name or filter hit every matching process on the machine, not just
# the ones the agent started. Only a PID tree you started may be killed.





# Judged per segment; a pipe stays in the segment so
# `Get-Process x | Stop-Process` is seen whole. Segments that only carry text
# (git/gh messages, grep, echo) are skipped unless they pipe into something.
# Ceiling: a speed bump, not a sandbox: CIM/wmic terminates, a pipeline split over
# lines, a process list kept in a variable across `;`, and a kill quoted on its own
# line of a multi-line message are not judged.
KILL_TEXT_VERB='^[[:space:](]*(git|gh|grep|rg|echo|printf|cat|Select-String|Write-Output|Write-Host)([[:space:]]|$)'
KILL_VERB='(^|[^[:alnum:]-])(stop-process|spps|kill)([[:space:]]|$)|\.kill\('
while IFS= read -r seg; do
    if ! grep -q '|' <<<"$seg" && grep -Eqi -- "$KILL_TEXT_VERB" <<<"$seg"; then continue; fi
    by_name=
    if grep -Eqi -- 'taskkill' <<<"$seg" &&
        grep -Eqi -- '[/-]+(im|fi)[[:space:]]' <<<"$seg"; then
        by_name=1
    elif grep -Eqi -- "$KILL_VERB" <<<"$seg" &&
        grep -Eqi -- '-(n|na|nam|name|processname)[[:space:]:]' <<<"$seg"; then
        by_name=1  # PowerShell accepts -n/-na/-nam for -Name
    elif grep -Eqi -- '(^|[^[:alnum:]-])(get-process|gps|ps)([[:space:])]|$)|getprocesses(byname)?[[:space:]]*\(' <<<"$seg" &&
        grep -Eqi -- "$KILL_VERB" <<<"$seg" &&
        ! grep -Eqi -- '(get-process|gps)[[:space:]]+-id[[:space:]:]' <<<"$seg"; then
        by_name=1  # a process list (by name or all) fed to a kill, unless fetched by -Id
    elif grep -Eqi -- '(^|[^[:alnum:]-])(pkill|killall|tskill|pskill)([[:space:]]|$)' <<<"$seg"; then
        by_name=1
    fi
    if [[ -n "$by_name" ]]; then
        echo "BLOCKED: killing processes by image name or filter." >&2
        echo "Command: $CMD" >&2



        echo "It kills every matching process on the machine, including other sessions." >&2
        echo "Kill only a process you started, by PID tree: taskkill /T /F /PID <pid> (or Stop-Process -Id <pid>)." >&2
        exit 2
    fi
done < <(printf '%s\n' "$CMD" | sed 's/||/\n/g' | tr ';&' '\n')

# Whole-disk and AppX operations: no target test — these are never routine here.
# Remove/Reset-AppxPackage re-registers the WindowsApps alias stubs (wt, winget,
# wsl); losing them breaks every Store CLI name on PATH.
PS_ALWAYS_DENY=(
    'Format-Volume'
    'Clear-Disk'
    'Remove-Partition'
    'Initialize-Disk'
    '(Remove|Reset)-AppxPackage'
)

for pattern in "${PS_ALWAYS_DENY[@]}"; do
    if grep -Eqi -- "$pattern" <<<"$CMD"; then
        echo "BLOCKED: Destructive Windows command pattern detected." >&2
        echo "Command: $CMD" >&2
        echo "Pattern matched: $pattern" >&2
        echo "If you really need this, run it manually outside Claude Code." >&2
        exit 2
    fi
done

exit 0
