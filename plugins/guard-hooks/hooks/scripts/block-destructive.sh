#!/usr/bin/env bash
# block-destructive.sh — PreToolUse hook for Bash and PowerShell commands
# Blocks known-destructive commands. Exit 0 = allow, Exit 2 = block.
# Both tools carry the command in tool_input.command, so one script guards both.

set -Eeuo pipefail
# An unexpected failure blocks: exit 1 is a non-blocking error, so the command would run.
trap 'exit 2' ERR
# ERR misses `set -u` and bad-substitution errors, which exit 1 and let the command run.
trap 'rc=$?; ((rc == 0 || rc == 2)) || exit 2' EXIT
# grep exits 2 on a pattern the local grep rejects (BSD grep and an empty group); inside an `if`
# that would read as "no match" and skip every check, so it blocks instead.
matches() { local rc=0; grep -Eq "$@" || rc=$?; ((rc < 2)) || exit 2; return "$rc"; }
# The clock for in_time starts before the input is even read.
START="${EPOCHREALTIME:-}"
START="${START//[.,]/}"

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
    ':\(\)[[:space:]]*\{'                      # fork bomb (any function named :)
    'curl[[:space:]]+.*\|[[:space:]]*sh'       # curl | sh
    'wget[[:space:]]+.*\|[[:space:]]*sh'       # wget | sh
    'sudo[[:space:]]+rm'                       # sudo rm
    'mkfs\.'                                   # filesystem format
    'dd[[:space:]]+.*of=/dev/'                 # dd to device
    '>/dev/sd[a-z]'                            # writing to block device
)

# One grep for all of them (each grep is a process); the loop only names the match.
args=()
for pattern in "${DENY_PATTERNS[@]}"; do args+=(-e "$pattern"); done
if matches "${args[@]}" <<<"$CMD"; then
    for pattern in "${DENY_PATTERNS[@]}"; do
        if matches -- "$pattern" <<<"$CMD"; then
            echo "BLOCKED: Destructive command pattern detected." >&2
            echo "Command: $CMD" >&2
            echo "Pattern matched: $pattern" >&2
            echo "If you really need this, run it manually outside Claude Code." >&2
            exit 2
        fi
    done
fi

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

args=()
for pattern in "${PS_ALWAYS_DENY[@]}"; do args+=(-e "$pattern"); done
if matches -i "${args[@]}" <<<"$CMD"; then
    for pattern in "${PS_ALWAYS_DENY[@]}"; do
        if matches -i -- "$pattern" <<<"$CMD"; then
            echo "BLOCKED: Destructive Windows command pattern detected." >&2
            echo "Command: $CMD" >&2
            echo "Pattern matched: $pattern" >&2
            echo "If you really need this, run it manually outside Claude Code." >&2
            exit 2
        fi
    done
fi

# The guards below judge statements. Every guard keeps the old quote-blind split
# (on ; & && || newlines, and | for the settings guard) as its floor; the readings
# added below can only add blocks, never lift one. The cheap old-style checks on the
# raw command run first, so a timeout (which lets the command run) can only cut off
# added checks. Per-statement checks use bash's own regex match, not a process each.
shopt -s nocasematch
blind() { # REPLY = the quote-blind split of <text>, one statement per line (no process)
    local t="$2" nl=$'\n'
    if [[ "$1" != 1 ]]; then t="${t//||/$nl}"; fi
    if [[ "$1" == 1 ]]; then REPLY="${t//[;|&]/$nl}"; else REPLY="${t//[;&]/$nl}"; fi
}
# The command is read three ways: as given (a carriage return inside a line, as the
# old hook saw it), with each carriage return as a statement break (PowerShell ends a
# statement there), and with a line ending in `|` or a backtick joined to the next
# (PowerShell continues the statement there).
# PowerShell also reads Unicode spaces as spaces, dashes U+2013-2015 as `-` and curly
# quotes as quotes, so a fourth reading has them in ASCII. NEL and the Unicode line and
# paragraph separators are not expected in a command at all.
if [[ "$CMD" == *$'\xc2\x85'* || "$CMD" == *$'\xe2\x80\xa8'* || "$CMD" == *$'\xe2\x80\xa9'* ]]; then
    echo "BLOCKED: command holds a Unicode line separator." >&2
    echo "Command: $CMD" >&2
    echo "Retype it with plain newlines." >&2
    exit 2
fi
ascii() { # REPLY = $1 with Unicode spaces, dashes and quotes in ASCII
    local t="$1" u sq="'" dq='"'
    for u in $'\xc2\xa0' $'\xe1\x9a\x80' $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83' \
        $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87' $'\xe2\x80\x88' $'\xe2\x80\x89' \
        $'\xe2\x80\x8a' $'\xe2\x80\xaf' $'\xe2\x81\x9f' $'\xe3\x80\x80'; do t="${t//$u/ }"; done
    for u in $'\xe2\x80\x93' $'\xe2\x80\x94' $'\xe2\x80\x95'; do t="${t//$u/-}"; done
    for u in $'\xe2\x80\x98' $'\xe2\x80\x99' $'\xe2\x80\x9a' $'\xe2\x80\x9b'; do t="${t//$u/$sq}"; done
    for u in $'\xe2\x80\x9c' $'\xe2\x80\x9d' $'\xe2\x80\x9e'; do t="${t//$u/$dq}"; done
    REPLY="$t"
}
# Past 4 s the hook nears its 5 s timeout, which lets the command run: block instead.
# The margin covers bash's own start and one slow step between checks. EPOCHREALTIME
# is bash 5 (its decimal mark follows the locale); older bash falls back to whole seconds.
in_time() {
    local now="${EPOCHREALTIME:-}"
    now="${now//[.,]/}"
    if { [[ -n "$START" && -n "$now" ]] && ((now - START > 4000000)); } || { [[ -z "$START" ]] && ((SECONDS >= 4)); }; then
        echo "BLOCKED: command took too long to judge." >&2
        echo "Command: ${CMD:0:200}" >&2
        echo "Split it up, or put it in a script file and run that." >&2
        exit 2
    fi
}
CONT_RE=$'[|`][ \t]*\n'
TEXTS=("$CMD")
# ($'..' inside ${..//..} in an array assignment is not expanded by every bash.)
CR=$'\r' NL=$'\n' EN=$'\xe2\x80\x93' EM=$'\xe2\x80\x94'
if [[ "$CMD" == *"$CR"* ]]; then TEXTS+=("${CMD//$CR/$NL}"); fi
ascii "${TEXTS[${#TEXTS[@]}-1]}"
if [[ "$REPLY" != "${TEXTS[${#TEXTS[@]}-1]}" ]]; then TEXTS+=("$REPLY"); fi
for text in "${TEXTS[@]}"; do
    if [[ "$text" =~ $CONT_RE ]]; then
        while [[ "$text" =~ $CONT_RE ]]; do
            in_time
            text="${text/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[0]:0:1} "}"
        done
        TEXTS+=("$text")
    fi
done
# A command that defines a function or alias can make any name (echo, cd, gc) run
# anything, so nothing in it counts as text-only or as a read.
DEFINES=
if [[ "$CMD" =~ (^|[^[:alnum:]_-])(function|filter|alias|sal|nal|Set-Alias|New-Alias)[[:space:]]|\(\)[[:space:]]*\{|function: ]]; then DEFINES=1; fi
STMTS=""
for text in "${TEXTS[@]}"; do blind 0 "$text"; STMTS+="$REPLY"$'\n'; done
lines="${STMTS//[!$NL]/}"
if ((${#lines} > 400)); then
    echo "BLOCKED: too many statements to judge in one command." >&2
    echo "Split it up, or put it in a script file and run that." >&2
    exit 2
fi

case_sensitive() { # case_sensitive <cmd...> — run a check with nocasematch off
    local r=0
    shopt -u nocasematch
    "$@" || r=1
    shopt -s nocasematch
    return "$r"
}
# shellcheck disable=SC2329  # called through case_sensitive
write_opt() { [[ "$1" =~ $HOOK_WRITE_OPT ]]; }
# git and gh read only through the subcommands below (options seen with quotes removed);
# the rest write the work tree or run a program (git -c, --exec-path, -O, pack options;
# gh alias, extension).
# shellcheck disable=SC2329  # called through case_sensitive
git_words() {
    local w i sub=
    read -ra w <<<"$1"
    for ((i = 1; i < ${#w[@]}; i++)); do
        case "${w[i]}" in
            -C | --git-dir | --work-tree | --namespace) if [[ -z "$sub" ]]; then i=$((i + 1)); fi ;;
            -c | --config-e* | --exe* | --upl* | --rece* | -O* | --op*) return 1 ;;
            -*) ;;
            *) if [[ -z "$sub" ]]; then sub="${w[i]}"; fi ;;
        esac
    done
    case "$sub" in
        add | blame | branch | cat-file | check-attr | check-ignore | commit | describe | diff | fetch | grep | log | ls-files | ls-tree | push | reflog | remote | rev-parse | shortlog | show | show-ref | status | tag) ;;
        rm) [[ "$1" == *--cached* ]] || return 1 ;;
        *) return 1 ;;
    esac
    [[ ! "$1" =~ [[:space:]]--output([[:space:]=]|$) ]]
}
gh_reads() {
    local w i
    read -ra w <<<"$1"
    for ((i = 1; i < ${#w[@]}; i++)); do
        [[ "${w[i]}" == -* ]] && continue
        case "${w[i]}" in
            issue | pr | run | release | repo | api | search | label | browse | status | workflow | gist | project | auth) return 0 ;;
            *) return 1 ;;
        esac
    done
    return 1
}
QUOTE_RE='^([^"'"'"']*)(["'"'"'])(.*)$'
outside_quotes() { # REPLY = $1 without its quoted parts (left to right, escapes ignored)
    local s="$1" out="" q
    while [[ "$s" =~ $QUOTE_RE ]]; do
        out+="${BASH_REMATCH[1]}" q="${BASH_REMATCH[2]}" s="${BASH_REMATCH[3]}"
        if [[ "$s" == *"$q"* ]]; then s="${s#*"$q"}"; else s=""; fi
    done
    REPLY="$out$s"
}
# Kills by image name or filter hit every matching process on the machine, not just
# the ones the agent started. Only a PID tree you started may be killed.





# Judged per segment; a pipe stays in the segment so
# `Get-Process x | Stop-Process` is seen whole. Segments that only carry text
# (git/gh messages, grep, echo) are skipped unless they pipe into something or hold
# a substitution.
# Ceiling: a speed bump, not a sandbox: CIM/wmic terminates, a process list kept in
# a variable across `;`, and a kill quoted on its own line of a multi-line message are
# not judged.
KILL_TEXT_VERB='^[[:space:](]*(git|gh|grep|rg|echo|printf|cat|Select-String|Write-Output|Write-Host)([[:space:]]|$)'
KILL_VERB='(^|[^[:alnum:]-])(stop-process|spps|kill)([[:space:]]|$)|\.kill\('
KILL_LIST='(^|[^[:alnum:]-])(get-process|gps|ps)([[:space:])]|$)|getprocesses(byname)?[[:space:]]*\('
KILL_BY_ID='(get-process|gps)[[:space:]]+-id[[:space:]:]'
KILL_IMFI='[/-]+(im|fi)[[:space:]]'
KILL_NAME='-(n|na|nam|name|processname)[[:space:]:]'
KILL_TOOL='(^|[^[:alnum:]-])(pkill|killall|tskill|pskill)([[:space:]]|$)'
GIT_RE='^[[:space:]]*\(?[[:space:]]*git([[:space:]]|$)'
GH_RE='^[[:space:]]*\(?[[:space:]]*gh([[:space:]]|$)'
kill_text() { # kill_text <statement> — only carries text, as the old hook skipped it
    # shellcheck disable=SC2016  # $( is a literal substitution opener
    [[ "$1" != *'|'* && "$1" != *'$('* && "$1" =~ $KILL_TEXT_VERB ]] || return 1
    [[ -z "$DEFINES" ]] || return 1
    local seg="$1"
    if ((${#seg} > 4096)); then REPLY="${seg//[\"\']/}"; else outside_quotes "$seg"; fi
    [[ "$REPLY" != *[\(\{]* ]] || return 1
    local flat="${1//[\"\']/}"
    if [[ "$flat" =~ $GIT_RE ]]; then case_sensitive git_words "$flat"; return; fi
    if [[ "$flat" =~ $GH_RE ]]; then gh_reads "$flat"; return; fi
    return 0
}
judge_kill() { # judge_kill <statements, one per line>
    local seg by_name
    while IFS= read -r seg; do
        in_time
        if kill_text "$seg"; then continue; fi
        by_name=
        if [[ "$seg" == *taskkill* && "$seg" =~ $KILL_IMFI ]]; then
            by_name=1
        elif [[ "$seg" =~ $KILL_VERB && "$seg" =~ $KILL_NAME ]]; then
            by_name=1  # PowerShell accepts -n/-na/-nam for -Name
        elif [[ "$seg" =~ $KILL_LIST && "$seg" =~ $KILL_VERB && ! "$seg" =~ $KILL_BY_ID ]]; then
            by_name=1  # a process list (by name or all) fed to a kill, unless fetched by -Id
        elif [[ "$seg" =~ $KILL_TOOL ]]; then
            by_name=1
        fi
        if [[ -n "$by_name" ]]; then
            echo "BLOCKED: killing processes by image name or filter." >&2
            echo "Command: $CMD" >&2



            echo "It kills every matching process on the machine, including other sessions." >&2
            echo "Kill only a process you started, by PID tree: taskkill /T /F /PID <pid> (or Stop-Process -Id <pid>)." >&2
            exit 2
        fi
    done <<<"$1"
}
judge_kill "$STMTS"

# PowerShell deletes are judged on TARGET, not verb. `Remove-Item -Recurse -Force
# bin, obj` is everyday work and must keep running; the same command aimed at a
# profile or system root must not.





# Root and recursion count from any statement (a cd into it, a variable holding it,
# text handed on); the delete verb counts from every statement but text-only ones
# (echo, printf, cat, grep, Select-String, Write-*, with no pipe, parenthesis,
# backtick, redirect or output variable, in a command defining no function or alias). En and em dashes count as dashes.
# Case-insensitive. `rm` stays out: in Git Bash it is everyday cleanup, often under the
# profile's temp folder; judge_rm below covers it on a whole profile. Ceiling: globs
# or 8.3 short names can reach a root unnamed.
DELETE_TEXT_VERB='^[[:space:]]*(echo|printf|cat|grep|Select-String|Write-Output|Write-Host)([[:space:]]|$)'
# An option that stores the output in a variable (-OutVariable, -ov, -iv, -pv, printf -v).
DELETE_TEXT_SETS='(^|[[:space:]])-[a-z]*v[a-z]*([[:space:]:]|$)'
PS_DELETE_VERB='Remove-Item|::Delete|\.Delete\(|(^|[^[:alnum:]_-])(rd|rmdir|ri|del|erase)([[:space:]]|$)'
# A .claude folder is a root bare or relative (the cwd may be the profile), after a
# `..`, under a user folder, or after a path part built from an expression; a
# project's own .claude folder is not.
# shellcheck disable=SC2016  # single quotes deliberate: \$env:/\$HOME are regex literals, not expansions



PS_PROTECTED_ROOT='\$\{?env:(USERPROFILE|LOCALAPPDATA|APPDATA|ProgramFiles|ProgramData|SystemRoot|windir|HOME)|%(USERPROFILE|LOCALAPPDATA|APPDATA|ProgramFiles|ProgramData|SystemRoot|windir|HOMEPATH)%|\$\{?HOME|~([/\)]|[[:space:]]|$)|[A-Z]:[/\]+(Users|Windows|Program Files|Documents and Settings)|/[a-z]/(Users|Windows|Program Files|Documents and Settings)|(^|[^[:alnum:]_])(Users|home)[/\]+[^/\]+[/\]+\.claude|\.\.[/\]+\.claude|[$(){}%][^[:space:]]*[/\]+\.claude|(^|[^[:alnum:]_./\-])(\.[/\]+)*\.claude\.?([^[:alnum:]_.-]|$)|(^|[^[:alnum:]_.-])WindowsApps([^[:alnum:]_.-]|$)'
# A bare cd, `cd ~` or `cd -` lands in the profile (or somewhere unknown).
PS_CD_HOME='^[[:space:]]*(cd|chdir|pushd|Set-Location|sl|Push-Location)([[:space:]]+[~-])?[[:space:]]*$'
# Recursive/bulk intent: -Recurse (or any prefix of it), -r/-rf, cmd-style /s, a
# wildcard, or a recursive $true. A single named file stays allowed.
# shellcheck disable=SC2016  # single quotes deliberate: \$true is a regex literal, not an expansion
PS_RECURSIVE='-Recurse|(^|[^[:alnum:]_-])Recurse([^[:alnum:]_]|$)|\.Delete\([^)[:space:]]|::Delete\([^,)]*,|(^|[^[:alnum:]_])-(re[a-z]*|-recursive|[dfiv]*r[dfiv]*)([^[:alnum:]_-]|$)|/s([^[:alnum:]_]|$)|\*|[,(][[:space:]]*\$true'
# A line ending like this, or with an open quote, carries its statement on to the next
# (`c=$(`, `$c =`), so the next line is not text on its own.
DELETE_CARRIES='([-=,({[+|`\\&]|(^|[[:space:]])-[[:alpha:]]+)[[:space:]]*$'
judge_delete() { # judge_delete <statements, one per line>
    local seg prev="" dq sq all="" nontext=""
    while IFS= read -r seg; do
        all+="$seg"$'\n'
        in_time
        dq="${prev//[!\"]/}" sq="${prev//[!\']/}"
        if [[ -z "$DEFINES" && "$seg" =~ $DELETE_TEXT_VERB && "$seg" != *[\|\(\)\{\}\`\>]* &&
            ! "$seg" =~ $DELETE_TEXT_SETS && ! "$prev" =~ $DELETE_CARRIES &&
            $((${#dq} % 2 + ${#sq} % 2)) == 0 ]]; then
            prev="$seg"
            continue
        fi
        if [[ -n "${seg//[[:space:]]/}" ]]; then prev="$seg"; fi
        nontext+="$seg"$'\n'
    done <<<"$1"
    all="${all//$EN/-}" all="${all//$EM/-}" all="${all//[\"\']/}"
    # A `.` path part is dropped, so it can't split a root from its drive or user folder.
    while [[ "$all" == *[/\\].[/\\]* ]]; do all="${all//[\/\\].[\/\\]/\/}"; done
    nontext="${nontext//$EN/-}" nontext="${nontext//$EM/-}" nontext="${nontext//[\"\']/}"
    # `--` is required: PS_RECURSIVE can start with "-", which grep would otherwise
    # parse as flags (including -r), silently recursing the cwd and matching anything.
    if [[ "$nontext" =~ $PS_DELETE_VERB ]] &&
        matches -i -e "$PS_PROTECTED_ROOT" -e "$PS_CD_HOME" <<<"$all" &&
        matches -i -- "$PS_RECURSIVE" <<<"$all"; then
        echo "BLOCKED: recursive delete aimed at a protected profile/system path." >&2
        echo "Command: $CMD" >&2



        echo "Protected roots: user profile, Windows, Program Files, .claude, WindowsApps." >&2
        echo "Delete a specific file, scope the delete to the project, or run it manually." >&2
        exit 2
    fi
}
judge_delete "$STMTS"





# A recursive `rm` (also PowerShell's rm alias) whose target is a whole profile, the
# profile's .claude, everything in one of them, or a `..` out of the profile.
# Paths below them (the profile's temp folder) stay allowed: in Git Bash rm is everyday
# cleanup. rm counts anywhere in a statement (`bash -c`, `sudo -u x`, `$(...)`), a
# target anywhere too (`echo ~ | xargs rm -rf`); text-only statements don't count.
RM_VERB='^([^[:space:]]*[/\])?rm(\.exe)?$'
RM_RECURSIVE='^(-[a-z]*r[a-z]*(:.*)?|--r[a-z]*(=.*)?)$'
# shellcheck disable=SC2016  # single quotes deliberate: \$HOME/\$env: are regex literals, not expansions
RM_BASE='(~|\$(HOME|USERPROFILE)|\$env:(USERPROFILE|HOME)|\$env:HOMEDRIVE\$env:HOMEPATH|%(USERPROFILE|HOMEPATH)%|%HOMEDRIVE%%HOMEPATH%|([/\][/\][?.][/\])?[a-z]:[/\]+Users[/\]+[^/\]+|[/\]+[a-z][/\]+Users[/\]+[^/\]+|[/\]+(Users|home)[/\]+[^/\]+)'



RM_ROOT="^($RM_BASE([/\]+\.claude)?|(\.[/\]+)*\.claude)([/\]+(\*|\.\*?))?[/\]*\$"
RM_UNDER="^$RM_BASE([/\\].*)\$"
# rm_up <path under a profile> — true when its `..` parts climb back to the profile or out.
rm_up() {
    local part depth=0
    [[ "$1" =~ $RM_UNDER && "$1" == *..* ]] || return 1
    local -a parts
    local rest="${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}"
    IFS=/ read -ra parts <<<"${rest//\\//}"
    for part in "${parts[@]}"; do
        case "$part" in
            '' | .) ;;
            ..) depth=$((depth - 1)); if ((depth < 0)); then return 0; fi ;;
            *) depth=$((depth + 1)) ;;
        esac
    done
    ((depth == 0))
}
# After a bare cd (the profile), everything in the cwd is the profile.
RM_HERE='^(\*|\.|\.[/\]+\*?)$'
RM_CD='^[[:space:]]*(cd|chdir|pushd|popd|Set-Location|sl|Push-Location|Pop-Location)([[:space:]]|$)'
RM_PARAM='^(.*)\$\{(env:)?(HOME|USERPROFILE|HOMEDRIVE|HOMEPATH)[^}]*\}(.*)$'
judge_rm() { # judge_rm <statements, one per line>
    local seg tok i is_rec is_root home=""
    local -a toks
    while IFS= read -r seg; do
        in_time
        if [[ "$seg" =~ $PS_CD_HOME ]]; then home=1; elif [[ "$seg" =~ $RM_CD ]]; then home=""; fi
        if [[ -z "$DEFINES" && "$seg" =~ $DELETE_TEXT_VERB && "$seg" != *[\|\(\)\{\}\`\>]* ]]; then continue; fi
        # git rm and a message naming rm are git's; a substitution or pipe still counts.
        # shellcheck disable=SC2016  # $( is a literal substitution opener
        if [[ -z "$DEFINES" && ( "$seg" =~ $GIT_RE || "$seg" =~ $GH_RE ) &&
            "$seg" != *'$('* && "$seg" != *[\`\|]* ]]; then continue; fi
        seg="${seg//$EN/-}" seg="${seg//$EM/-}" seg="${seg//[\"\']/}" seg="${seg//[()\`|]/ }"
        read -ra toks <<<"$seg"
        for ((i = 0; i < ${#toks[@]}; i++)); do
            tok="${toks[i]//\\/}"
            if [[ "$tok" =~ $RM_VERB ]]; then break; fi
        done
        if ((i >= ${#toks[@]})); then continue; fi
        is_rec="" is_root=""
        for tok in "${toks[@]:i+1}"; do
            if [[ "$tok" =~ $RM_RECURSIVE ]]; then is_rec=1; fi
        done
        for tok in "${toks[@]}"; do
            while [[ "$tok" =~ $RM_PARAM ]]; do
                tok="${BASH_REMATCH[1]}\$${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
            done
            while [[ "$tok" == *[/\\].[/\\]* ]]; do tok="${tok//[\/\\].[\/\\]/\/}"; done
            if [[ "$tok" =~ $RM_ROOT ]] || rm_up "$tok" ||
                { [[ -n "$home" ]] && [[ "$tok" =~ $RM_HERE ]]; }; then is_root=1; fi
        done
        if [[ -n "$is_rec" && -n "$is_root" ]]; then
            echo "BLOCKED: recursive rm aimed at a whole user profile or its .claude folder." >&2
            echo "Command: $CMD" >&2
            echo "Delete a specific folder inside it, or run it manually." >&2
            exit 2
        fi
    done <<<"$1"
}
judge_rm "$STMTS"

# Simple assignments (`name=value`, `$name = value`) are substituted, in order, into the
# `$name` / `${name...}` uses after them. The expanded text is judged as well as the
# original, so a decoy assignment can only add evidence. Capped (16 KB, 500 `$`, 50
# assignments, 4 KB a value) so doubled values or many uses can't stall the hook.
ASSIGN_RE='(^|[[:space:];&|(])[A-Za-z_][A-Za-z0-9_]*=([^[:space:];&|"'"'"']|"[^"]*"|'"'"'[^'"'"']*'"'"')*|\$\{?[A-Za-z_][A-Za-z0-9_:]*\}?[[:space:]]*=[^=;&|][^;&|]*'
VAR_NAMES=() VAR_VALS=()
subst_vars() { # REPLY = $1 with the known variables substituted; fails past 16 KB
    local t="$1" n out k
    for ((k = 0; k < ${#VAR_NAMES[@]}; k++)); do
        n="${VAR_NAMES[k]}" out=""
        while [[ "$t" =~ ^(.*)\$\{$n([^A-Za-z0-9_:}][^}]*)?\}(.*)$ ]]; do
            out="${VAR_VALS[k]}${BASH_REMATCH[3]}$out" t="${BASH_REMATCH[1]}"
            ((${#out} <= 16384)) || return 1
        done
        t="$t$out" out=""
        while [[ "$t" =~ ^(.*)\$$n([^A-Za-z0-9_:].*)?$ ]]; do
            out="${VAR_VALS[k]}${BASH_REMATCH[2]}$out" t="${BASH_REMATCH[1]}"
            ((${#out} <= 16384)) || return 1
        done
        t="$t$out"
    done
    REPLY="$t"
}
expand_vars() { # EXP = $1 expanded, or $1 itself past a cap
    local LC_ALL=C s="$1" out="" pos=0 m off a end name count=0 list dollars k grc
    EXP="$1"
    dollars="${s//[!\$]/}"
    ((${#s} <= 16384 && ${#dollars} <= 256)) || return 0
    # No match (1) is fine; a grep error (2) would skip the variable checks, so it blocks.
    list="$(grep -Ebo -- "$ASSIGN_RE" <<<"$s")" || { grc=$?; ((grc == 1)) || exit 2; }
    while IFS= read -r m; do
        [[ -n "$m" ]] || continue
        count=$((count + 1))
        ((count <= 50)) || return 0
        off="${m%%:*}" a="${m#*:}"
        end=$((off + ${#a}))
        ((off >= pos)) || continue
        subst_vars "${s:pos:end-pos}" || return 0
        out+="$REPLY"
        ((${#out} <= 16384)) || return 0
        name="${a%%=*}"
        name="${name#"${name%%[![:space:];&|(]*}"}"
        name="${name#\$}" name="${name#\{}"
        name="${name%"${name##*[![:space:]]}"}" name="${name%\}}"
        a="${a#*=}" a="${a#"${a%%[![:space:]]*}"}"
        subst_vars "${a//[\"\']/}" || return 0
        if [[ -n "$name" ]] && ((${#REPLY} <= 4096)); then
            for ((k = 0; k < ${#VAR_NAMES[@]}; k++)); do [[ "${VAR_NAMES[k]}" != "$name" ]] || break; done
            VAR_NAMES[k]="$name" VAR_VALS[k]="$REPLY"
        fi
        pos=$end
    done <<<"$list"
    subst_vars "${s:pos}" || return 0
    out+="$REPLY"
    if ((${#out} <= 16384)); then EXP="$out"; fi
}
expand_vars "${TEXTS[${#TEXTS[@]}-1]}"
if [[ "$EXP" != "${TEXTS[${#TEXTS[@]}-1]}" ]]; then
    TEXTS+=("$EXP")
    blind 0 "$EXP"
    ESTMTS="$REPLY"
    judge_kill "$ESTMTS"
    judge_delete "$STMTS$ESTMTS"
    judge_rm "$ESTMTS"
fi

# Hook wiring: a shell command that rewrites Claude Code settings, the harness hook
# folder or the plugin-cache hook folder can switch off every guard (a prompt-injection
# path). Read allowlist per command segment: a segment naming a protected target
# must start with a read verb (or git/gh: commit messages mention these paths) and
# have no output redirect onto the target. Everything else touching a target is blocked.
# Also blocked: a copy, move or download into the .claude, harness or plugins folder
# itself, and, after a cd into one of those, every statement that is not a read or
# writes with `>`. Besides the quote-blind split, SPLIT_AWK reads the command
# quote-aware (so a write inside `python -c "..."` stays with python) and with pipes
# kept (so every stage of a pipe that names a target must read or filter). A command
# over 16 KB that names .claude is blocked rather than read slowly.
# Ceiling: a speed bump, not a sandbox: paths built by a program, globs and 8.3 short
# names are not followed.
# shellcheck disable=SC2016  # awk program: $ and ` are awk/shell text, not expansions
SPLIT_AWK='
function emit() { gsub(/\n/, " ", cur); if (cur ~ /[^ \t]/) print cur; cur = "" }
{ s = s $0 "\n" }
END {
    esc = (dialect == "pwsh") ? "`" : "\\"
    n = length(s); nl = split(s, L, "\n"); ln = 0; q = ""; hd = ""; pend = 0; cur = ""
    for (i = 1; i <= n; i++) {
        if (q == "H") {
            line = L[ln + 1]; i += length(line); ln++
            t = line; if (tabs) sub(/^\t+/, "", t)
            if (t == hd || (hd ~ /@$/ && index(line, hd) == 1)) { q = ""; cur = cur " " line; emit(); continue }
            if (lit) { gsub(/`/, " ", line); gsub(/[$<>]\(/, " ", line) } else gsub(/\$\(/, "\001", line)
            gsub(/\(/, " ", line); gsub(/\001/, "$(", line)
            cur = cur " " line; continue
        }
        c = substr(s, i, 1); if (c == "\n") ln++
        if (q == "'"'"'") { cur = cur c; if (c == q) q = ""; continue }
        if (c == esc && i < n) {
            if (substr(s, i + 1, 1) == "\n") ln++
            cur = cur c substr(s, i + 1, 1); i++; continue
        }
        if (q == "\"") { cur = cur c; if (c == q) q = ""; continue }
        p = (i > 1) ? substr(s, i - 1, 1) : "\n"
        if (c == "#" && p ~ /[ \t\n;&|(<]/) bad = 1
        if (c == "'"'"'" || c == "\"") {
            if (dialect == "pwsh" && p == "@") {
                r = substr(s, i + 1); sub(/\n.*/, "", r)
                if (r ~ /^[ \t]*$/) { q = "H"; hd = c "@"; tabs = 0; lit = (c == "'"'"'"); cur = cur c; i += length(r) + 1; ln++; continue }
            }
            q = c; cur = cur c; continue
        }
        if (c == "<" && substr(s, i + 1, 2) == "<<") { cur = cur "<<<"; i += 2; continue }
        if (c == "<" && substr(s, i + 1, 1) == "<") {
            k = i + 2; tabs = 0
            if (substr(s, k, 1) == "-") { tabs = 1; k++ }
            while (substr(s, k, 1) ~ /[ \t]/) k++
            d = substr(s, k, 1); lit = 0
            if (d == "\\") { lit = 1; k++; d = substr(s, k, 1) }
            if (d == "'"'"'" || d == "\"") {
                lit = 1; e = index(substr(s, k + 1), d); hd = substr(s, k + 1, e - 1)
                if (e == 0 || index(hd, "\n")) { bad = 1; hd = "" } else k += e + 1
            } else if (match(substr(s, k), /^[A-Za-z0-9_.-]+/)) {
                hd = substr(s, k, RLENGTH); k += RLENGTH
            } else hd = ""
            if (hd == "" || (k <= n && substr(s, k, 1) !~ /[ \t\n;&|<>()]/)) bad = 1
            else pend = 1
            cur = cur substr(s, i, k - i); i = k - 1; continue
        }
        if (c == "\n" && pend) { pend = 0; q = "H"; continue }
        if (c == ";" || c == "\n") { emit(); continue }
        if (c == "&") {
            if (cur ~ /[<>]$/ || substr(s, i + 1, 1) == ">") { cur = cur c; continue }
            if (substr(s, i + 1, 1) == "&") i++
            emit(); continue
        }
        if (c == "|") {
            if (substr(s, i + 1, 1) == "|") { i++; emit(); continue }
            if (pipes) { emit(); continue }
        }
        cur = cur c
    }
    if (q != "" || pend || bad) print "@@UNBALANCED@@"
    emit()
}'
statements() { # statements <pipes> <text> — the quote-aware readings, both dialects
    local b p
    b="$(printf '%s' "$2" | LC_ALL=C awk -v dialect=bash -v pipes="$1" "$SPLIT_AWK")" || b=""
    p="$(printf '%s' "$2" | LC_ALL=C awk -v dialect=pwsh -v pipes="$1" "$SPLIT_AWK")" || p=""
    printf '%s\n%s\n' "$b" "$p"
}
HOOK_TARGET='\.claude[/\]+(settings(\.local)?\.json|harness[/\]+hooks|plugins[/\][^[:space:]"'"'"']*hooks)'
HOOK_REDIRECT=">[^>]*($HOOK_TARGET)"
HOOK_DIR='\.claude([/\]+(harness|plugins))?[/\]*([[:space:];&|)]|$)'
HOOK_COPY_VERB='^[[:space:]]*(cp|mv|Copy-Item|cpi|copy|Move-Item|mi|move|xcopy|robocopy|rsync|install|ln|tar|unzip|7z|Expand-Archive|curl|wget|aria2c|iwr|Invoke-WebRequest|Start-BitsTransfer|New-Item|ni|mklink)([[:space:]]|$)'
HOOK_CD_VERB='^[[:space:]\{(]*((builtin|command)[[:space:]]+)?(cd|chdir|pushd|Set-Location|sl|Push-Location)([[:space:]]|$)'
HOOK_CD_INTO='\.claude([/\]+(harness|plugins)[^[:space:];&|]*)?([/\]+\.\.?)*[/\]*([[:space:])}]|$)'
# A redirect that writes nowhere: to /dev/null, $null, or one stream into another.
# shellcheck disable=SC2016  # \$null is a regex literal
NULL_REDIRECT_RE='^(.*)>+[[:space:]]*(/dev/null|\$null|&[0-9])(.*)$'
writes_out() { # writes_out <text> — holds a > redirect that writes a file
    local t="$1"
    while [[ "$t" =~ $NULL_REDIRECT_RE ]]; do t="${BASH_REMATCH[1]} ${BASH_REMATCH[3]}"; done
    [[ "$t" == *'>'* ]]
}
HOOK_READ_VERB='^[[:space:](]*(cat|type|less|head|tail|grep|rg|jq|Get-Content|gc|Select-String|ls|dir|Get-ChildItem|Test-Path|diff|code|git|gh|wc|stat)([[:space:]]|$)'
# wc and stat joined the read verbs; nothing looser does: copy-out, path assignments and
# `sed -n` all had write variants (flags hidden by quotes, braces, $IFS, `~`/HOME expansion).
# Use `head -n M FILE | tail -n +N` for a line range. A substitution runs code inside a read.
# Later stages of a reading pipe may also filter (a { } script block never counts).
HOOK_PIPE_FILTER='^[[:space:]]*(sort|Sort-Object|uniq|cut|tr|nl|column|more|findstr|base64|sha256sum|md5sum|Select-Object|select|Where-Object|where|ConvertFrom-Json|ConvertTo-Json|Format-List|fl|Format-Table|ft|Out-String|Out-Host|Measure-Object|measure|Get-FileHash)([[:space:]]|$)'
# Read verbs with a write or run option: gh downloads, clones and codespace copies,
# rg --pre and --hostname-bin run a program, less -o writes a log. Case-sensitive.
HOOK_WRITE_OPT='^[[:space:]]*(gh[[:space:]].*[[:space:]]+(download|clone|checkout|codespace|cp)([[:space:]]|$)|gh([[:space:]].*)?[[:space:]]-(O|D|-output|-dir)([[:space:]=]|$)|rg[[:space:]].*--(pre|hostname-bin)([[:space:]=]|$)|less([[:space:]].*)?[[:space:]]+(-[a-zA-Z]*[oO]|--log-file|--LOG-FILE))'
reads() { # reads <statement> — a read (or a cd) with no write or program-running option
    local s="$1" flat="${1//[\"\']/}"
    # shellcheck disable=SC2016  # $( and ` are literal substitution openers
    if [[ "$s" == *'$('* || "$s" == *'`'* || "$s" == *'<('* || "$s" == *'>('* ]]; then return 1; fi
    # PowerShell runs a bare ( ) group and a { } script block. With an escaped quote, or
    # past 4 KB (kept linear), the quoting isn't trusted and the quoted text counts too.
    if [[ "$s" == *[\\\`][\"\']* || "$s" == *'<#'* ]] || ((${#s} > 4096)); then REPLY="$flat"; else outside_quotes "$s"; fi
    if [[ "$REPLY" == *[\(\{]* ]]; then return 1; fi
    if [[ "$flat" =~ $HOOK_CD_VERB ]]; then return 0; fi
    [[ "$s" =~ $HOOK_READ_VERB ]] || return 1
    if case_sensitive write_opt "$s"; then return 1; fi
    if [[ "$flat" =~ ^[[:space:]]*git([[:space:]]|$) ]]; then case_sensitive git_words "$flat"; return; fi
    if [[ "$flat" =~ ^[[:space:]]*gh([[:space:]]|$) ]]; then gh_reads "$flat"; return; fi
    return 0
}
pipe_reads() { # pipe_reads <statement> — every stage of the pipe (split outside quotes) reads
    local LC_ALL=C s="$1" stage="" c q="" i first=1 blind=
    # A <# comment can hold a quote, so its quoting isn't trusted: split on every |.
    if [[ "$s" == *'<#'* ]]; then blind=1; fi
    for ((i = 0; i <= ${#s}; i++)); do
        c="${s:i:1}"
        if [[ -n "$blind" && ( "$c" == "'" || "$c" == '"' ) ]]; then
            :
        elif [[ -n "$q" ]]; then
            [[ "$c" == "$q" ]] && q=""
        elif [[ "$c" == "'" || "$c" == '"' ]]; then
            q="$c"
        elif [[ "$c" == '|' || -z "$c" ]]; then
            in_time
            if [[ -n "$first" ]]; then
                reads "$stage" || return 1
            elif ! reads "$stage"; then
                outside_quotes "$stage"
                [[ "$stage" =~ $HOOK_PIPE_FILTER && "$REPLY" != *[\(\{]* ]] || return 1
            fi
            first="" stage=""
            continue
        fi
        stage+="$c"
    done
}
judge_settings() { # judge_settings <pipes-kept> — reads statements on stdin; blocks on a write
    local seg flat cdc=""
    while IFS= read -r seg; do
        in_time
        flat="${seg//[\"\']/}"
        if [[ -n "$cdc" && "$flat" =~ [^[:space:]] ]] || [[ "$flat" =~ $HOOK_TARGET ]] ||
            { [[ "$flat" =~ $HOOK_DIR ]] && [[ "$flat" =~ $HOOK_COPY_VERB || "$flat" =~ $HOOK_WRITE_OPT ]]; }; then
            if { [[ "$1" == 1 && "$seg" == *'|'* ]] && ! pipe_reads "$seg"; } || ! reads "$seg" ||
                [[ "$flat" =~ $HOOK_REDIRECT ]] ||
                { [[ -n "$cdc" ]] && writes_out "$flat"; }; then
                echo "BLOCKED: shell write to Claude Code settings or hook folders." >&2
                echo "Command: $CMD" >&2
                echo "Edit these files manually outside Claude Code." >&2
                exit 2
            fi
        fi
        if [[ "$flat" =~ $HOOK_CD_VERB && "$flat" =~ $HOOK_CD_INTO ]]; then cdc=1; fi
    done
}
# Every target names .claude, so without it (quotes removed) there is nothing to judge.
flat_all=""
for text in "${TEXTS[@]}"; do flat_all+="${text//[\"\']/} "; done
if [[ "$flat_all" == *.claude* ]]; then
    if [[ -n "$DEFINES" ]]; then
        echo "BLOCKED: a command that defines a function or alias and names .claude." >&2
        echo "Command: $CMD" >&2
        echo "Edit these files manually outside Claude Code." >&2
        exit 2
    fi
    if ((${#CMD} > 16384)); then
        echo "BLOCKED: command over 16 KB that names .claude; too long to judge in time." >&2
        echo "Command: ${CMD:0:200}..." >&2
        echo "Split it up, or put it in a script file and run that." >&2
        exit 2
    fi
    for text in "${TEXTS[@]}"; do
        blind 1 "$text"
        judge_settings 0 <<<"$REPLY"
        judge_settings 0 <<<"$(statements 1 "$text")"
        judge_settings 1 <<<"$(statements 0 "$text")"
    done
fi

exit 0
