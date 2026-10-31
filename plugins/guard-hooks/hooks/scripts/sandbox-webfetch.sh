#!/usr/bin/env bash
# sandbox-webfetch.sh — PreToolUse hook for WebFetch
# Validates the URL against an allowlist and danger patterns.
# Logs scheme and host (never the path) to ~/.claude/harness/audit/audit-<project>.log (outside the repo). Exit 0 = allow, Exit 2 = block; "prompt" = exit 0 with a
# PreToolUse permissionDecision "ask" on stdout (Claude Code treats exit 1 as a
# non-blocking error, so it never prompted).
# SANDBOX_WEBFETCH_MODE=interactive (plugin hooks.json) -> rate caps ask instead of block.
#



# Allowlist: vendor docs, security references, StackOverflow and MDN (see ALLOWLIST below)

set -euo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
    # shellcheck disable=SC1090,SC1091
    . "$(dirname "${BASH_SOURCE[0]}")/read-tool-input.sh"
    URL="$(read_tool_input_field url)"
fi
if [[ -z "$URL" ]]; then
    exit 0
fi

MODE="${SANDBOX_WEBFETCH_MODE:-autonomous}"

ask_user() {
    # JSON-escape by hand: backslash, quote, then control characters.
    local reason="${1//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    reason="${reason//[[:cntrl:]]/ }"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$reason"
    exit 0
}

cap_hit() {
    if [[ "$MODE" == "interactive" ]]; then ask_user "$1"; fi
    echo "BLOCKED by sandbox-webfetch: $1" >&2
    exit 2
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"



# Normalised so the log file name is stable across path styles.
[[ -n "$PROJECT_DIR" ]] && PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -W 2>/dev/null || pwd -P 2>/dev/null || echo "$PROJECT_DIR")"
AUDIT_LOG=""
if [[ -n "$PROJECT_DIR" ]] && mkdir -p "$HOME/.claude/harness/audit" 2>/dev/null; then
    AUDIT_LOG="$HOME/.claude/harness/audit/audit-$(basename "$PROJECT_DIR").log"
fi

log_audit() {
    local result="$1"
    local detail="$2"
    if [[ -n "$AUDIT_LOG" ]]; then
        local ts
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        # Tokens live in the query, the fragment, user:pass@ and also the path (bot tokens, webhooks,
        # presigned links): log scheme and host only.
        local sanitized_url="${URL%%[?#]*}"
        sanitized_url="${sanitized_url//[[:cntrl:][:space:]]/}" # a newline in the URL must not forge a log line
        if [[ "$sanitized_url" == *://* ]]; then
            local rest="${sanitized_url#*://}"
            local host="${rest%%/*}"
            sanitized_url="${sanitized_url%%://*}://${host##*@}"
        else
            sanitized_url="(malformed url)"
        fi
        echo "$ts | $MODE | WebFetch | $sanitized_url | $result | $detail" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
}

# --- 0. Parser-differential characters ---
# Whitespace, control characters and backslashes are read differently by this hook and by the fetcher
# (a WHATWG parser turns a backslash into a slash, so evil.example-backslash-.github.com fetches evil.example).
BAD_CHARS='[[:space:][:cntrl:]\]'
if [[ "$URL" =~ $BAD_CHARS ]]; then
    log_audit "BLOCKED" "bad-char"
    echo "BLOCKED by sandbox-webfetch: URL contains whitespace, a control character or a backslash" >&2
    exit 2
fi

# --- 1. HTTPS-only check ---
if [[ ! "$URL" =~ ^https:// ]]; then
    log_audit "BLOCKED" "non-https"
    echo "BLOCKED by sandbox-webfetch: non-https URL — only HTTPS auto-allowed" >&2
    echo "URL: $URL" >&2
    exit 2
fi

# --- 2. Credentials-in-URL check ---
if [[ "$URL" =~ ^https://[^/]*[:@] ]]; then
    log_audit "BLOCKED" "credentials-in-url"
    echo "BLOCKED by sandbox-webfetch: URL contains embedded credentials" >&2
    exit 2
fi

# --- 3. Data exfiltration patterns in query parameters ---
# Long base64 / hex strings in query → potential exfiltration channel
QUERY="${URL#*\?}"
if [[ "$QUERY" != "$URL" ]]; then
    # Has a query string. Check for suspicious long encoded strings.
    if grep -Eq '[A-Za-z0-9+/]{50,}={0,2}' <<<"$QUERY"; then
        log_audit "BLOCKED" "suspicious-query-base64"
        echo "BLOCKED by sandbox-webfetch: query contains long base64-like string (potential exfiltration)" >&2
        exit 2
    fi
    if grep -Eq '[a-fA-F0-9]{40,}' <<<"$QUERY"; then
        log_audit "BLOCKED" "suspicious-query-hex"
        echo "BLOCKED by sandbox-webfetch: query contains long hex string (potential exfiltration)" >&2
        exit 2
    fi
fi

# --- 4. Extract hostname ---
HOST="$(echo "$URL" | sed -E 's|^https://([^/?#]+).*|\1|' | sed -E 's|:[0-9]+$||')"
HOST_LC="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"

# --- 5. Allowlist check ---
# Format: exact match or matches *.domain.tld
ALLOWLIST=(
    "docs.anthropic.com"
    "code.claude.com"
    "platform.claude.com"
    "github.com"
    "api.github.com"
    "raw.githubusercontent.com"





    "learn.microsoft.com"
    "owasp.org"
    "genai.owasp.org"
    "nist.gov"
    "csrc.nist.gov"
    "atlas.mitre.org"
    "stackoverflow.com"
    "developer.mozilla.org"
)

ALLOWED=0
for allowed_domain in "${ALLOWLIST[@]}"; do
    if [[ "$HOST_LC" == "$allowed_domain" ]]; then
        ALLOWED=1
        break
    fi
    # Allow subdomains of github.com, nist.gov, mozilla.org
    case "$allowed_domain" in
        github.com|nist.gov|developer.mozilla.org)
            if [[ "$HOST_LC" == *".$allowed_domain" ]]; then
                ALLOWED=1
                break
            fi
            ;;
    esac
done

if [[ $ALLOWED -eq 0 ]]; then
    log_audit "PROMPT" "off-allowlist:$HOST_LC"
    ask_user "sandbox-webfetch: host '$HOST_LC' is not on the allowlist"
fi

# --- 6. Per-session fetch cap (10) ---
# ISO-8601 UTC timestamps sort lexicographically, so a string compare against a
# UTC cutoff is timezone-proof. (gawk mktime() parsed the UTC log timestamps as
# LOCAL time, silently disabling both caps in any UTC+ timezone.)
if [[ -n "$AUDIT_LOG" && -f "$AUDIT_LOG" ]] \
   && CUTOFF_TS="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
    FETCH_COUNT_LAST_HOUR=$(awk -F' \\| ' -v cutoff="$CUTOFF_TS" '
        $3 == "WebFetch" && $1 >= cutoff { count++ }
        END { print count+0 }
    ' "$AUDIT_LOG" 2>/dev/null)

    if [[ "$FETCH_COUNT_LAST_HOUR" -ge 10 ]]; then
        log_audit "BLOCKED" "session-cap-exceeded:$FETCH_COUNT_LAST_HOUR"
        cap_hit "session fetch cap reached (10 per hour); review what was fetched"
    fi

    # Per-domain hourly cap (10 same domain)
    SAME_DOMAIN_COUNT=$(awk -F' \\| ' -v cutoff="$CUTOFF_TS" -v host="$HOST_LC" '
        $3 == "WebFetch" && index($4, host) > 0 && $1 >= cutoff { count++ }
        END { print count+0 }
    ' "$AUDIT_LOG" 2>/dev/null)

    if [[ "$SAME_DOMAIN_COUNT" -ge 10 ]]; then
        log_audit "BLOCKED" "domain-cap-exceeded:$HOST_LC:$SAME_DOMAIN_COUNT"
        cap_hit "$HOST_LC fetched ${SAME_DOMAIN_COUNT}+ times in the last hour"
    fi
fi

log_audit "ALLOWED" "$HOST_LC"
exit 0
