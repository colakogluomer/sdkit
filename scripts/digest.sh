#!/usr/bin/env bash
# Bounded views of long text for the orchestrator's context (F09). The FULL text is always kept on disk and named in the view; a failure line
# is never dropped. Nothing here judges anything: the verdict still comes from parse-verdict.sh, on the full answer.
# Usage:
#   digest.sh output [--max N] [--ref FILE] [--label L]   stdin = a command's output. <= N lines (default 60) pass through unchanged. Longer: the
#                                                          first 10 lines, EVERY failure line (FAIL|ERROR|panic|Traceback|error:|not ok|BLOCK|CONFIRMED|
#                                                          exception, up to 80), the last 15 lines, and the path of the full text.
#   digest.sh envelope --role R [--file F] --ref FILE      stdin or F = a role's final answer. Prints a compact envelope instead of it:
#                                                          ENVELOPE/1 role= decision= dod= findings= evidence=<FILE> bytes=full/shown
#                                                          then every FAIL / CONFIRMED / BLOCKER / CRITICAL / HIGH / NEEDS-LOOKUP / HANDOFF-RESULT line
#                                                          verbatim, then (free-form roles) the first 12 lines, then NEXT: <what to do>.
#                                                          --ref is written with the full answer if it does not exist yet.
#   digest.sh stats [slug]                                 bytes kept off the orchestrator's context so far (work/<slug>/context.jsonl)
# A short answer (<= ENVELOPE_MIN_BYTES, default 1500) is printed unchanged: an envelope would be larger than it.
# The views are passed through redact.sh (credential-shaped strings become [REDACTED:..]); the full text on disk is untouched.
# Sizes are written to <project-dir>/work/<slug>/context.jsonl (kind, full_bytes, shown_bytes; no text). Set DIGEST_STATS=0 to skip that.
# Exit: 0 ok, 2 usage.
set -u
mode="${1:-}"; shift 2>/dev/null || true
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; top="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
KIT_DIR=.sdkit; slug=""
if [ -f "$here/env.sh" ]; then . "$here/env.sh" 2>/dev/null; SDKIT_ENV_QUIET=1 sdkit_env_load "$top" 2>/dev/null; slug="$(sdkit_active_slug "$top" 2>/dev/null || true)"; fi
FAILRE='FAIL|ERROR|[Pp]anic|Traceback|error:|not ok|BLOCK|CONFIRMED|[Ee]xception|CRITICAL|Segmentation'
note() {  # <kind> <full bytes> <shown bytes>
  [ "${DIGEST_STATS:-1}" = 0 ] && return 0
  local d="$top/$KIT_DIR/work/${slug:-_none}"; mkdir -p "$d" 2>/dev/null || return 0
  printf '{"ts":"%s","kind":"%s","full_bytes":%s,"shown_bytes":%s}\n' "$(date -u +%FT%TZ)" "$1" "$2" "$3" >> "$d/context.jsonl" 2>/dev/null; return 0
}
max=60; ref=""; role=""; file=""; label=out
while [ $# -gt 0 ]; do case "$1" in --max) max="$2"; shift ;; --ref) ref="$2"; shift ;; --role) role="$2"; shift ;; --file) file="$2"; shift ;; --label) label="$2"; shift ;; *) [ "$mode" = stats ] && slug="$1" || { echo "digest: unknown option $1" >&2; exit 2; } ;; esac; shift; done
newref() { [ -n "$ref" ] || { mkdir -p "$top/$KIT_DIR/work/${slug:-_none}/out" 2>/dev/null; ref="$top/$KIT_DIR/work/${slug:-_none}/out/$label-$(date +%s)-$$.txt"; }; }
case "$mode" in
  output)
    tmp="$(mktemp)"; cat > "$tmp"; n="$(wc -l < "$tmp" | tr -d ' ')"; fb="$(wc -c < "$tmp" | tr -d ' ')"
    if [ "$n" -le "$max" ]; then cat "$tmp"; note output "$fb" "$fb"; rm -f "$tmp"; exit 0; fi
    newref; mkdir -p "$(dirname "$ref")"; cp "$tmp" "$ref"
    v="$( { head -10 "$tmp"; echo "@@SEP@@"; grep -nE "$FAILRE" "$tmp" | head -80 | cut -c1-300; echo "@@SEP@@"; tail -15 "$tmp"; } )"
    printf '%s\n' "$v" | "$here/redact.sh" | awk '/^@@SEP@@$/ { s++; if (s == 1) print "[... failure lines of the full text (line: text) ...]"; if (s == 2) print "[... last 15 lines ...]"; next } { print }'
    echo "[digest: $n lines, $fb bytes kept; the full text is in $ref]"
    shown=$(printf '%s\n' "$v" | wc -c | tr -d ' '); note output "$fb" "$shown"; rm -f "$tmp" ;;
  envelope)
    [ -n "$role" ] || { echo "usage: digest.sh envelope --role R [--file F] --ref FILE" >&2; exit 2; }
    tmp="$(mktemp)"; if [ -n "$file" ]; then cat "$file" > "$tmp"; else cat > "$tmp"; fi; fb="$(wc -c < "$tmp" | tr -d ' ')"
    if [ "$fb" -le "${ENVELOPE_MIN_BYTES:-1500}" ]; then cat "$tmp"; note envelope "$fb" "$fb"; rm -f "$tmp"; exit 0; fi   # a short answer is already its own envelope
    newref; mkdir -p "$(dirname "$ref")"; [ -f "$ref" ] || cp "$tmp" "$ref"
    clean="$(tr -d '\r' < "$tmp" | grep -v '^[[:space:]]*```')"
    dec="$(printf '%s\n' "$clean" | sed -nE 's/^[[:space:]]*[*_]*VERDICT[*_]*[[:space:]]*:?[*_[:space:]]*:?[[:space:]]*[*_`]*(PASS|BLOCK|pass|block)[*_`]*[[:space:]]*$/\1/p' | tail -1 | tr a-z A-Z)"; [ -n "$dec" ] || dec=none
    dp="$(printf '%s\n' "$clean" | grep -ciE '\|[[:space:]]*[*_]*PASS[*_]*[[:space:]]*(\||$)' || true)"; df="$(printf '%s\n' "$clean" | grep -ciE '\|[[:space:]]*[*_]*FAIL[*_]*[[:space:]]*(\||$)' || true)"
    fc="$(printf '%s\n' "$clean" | grep -ciE '^[[:space:]]*-[[:space:]]*CONFIRMED' || true)"; fp="$(printf '%s\n' "$clean" | grep -ciE '^[[:space:]]*-[[:space:]]*PLAUSIBLE' || true)"
    crit="$(printf '%s\n' "$clean" | grep -cE '^[[:space:]]*([-*]|[0-9]+[.)])?[[:space:]]*[*_]*(BLOCKER|CRITICAL|HIGH)[*_]*[[:space:]]*\|' || true)"
    keep="$(printf '%s\n' "$clean" | grep -E '\|[[:space:]]*[*_]*FAIL|^[[:space:]]*-[[:space:]]*CONFIRMED|^[[:space:]]*([-*]|[0-9]+[.)])?[[:space:]]*[*_]*(BLOCKER|CRITICAL|HIGH)[*_]*[[:space:]]*\||NEEDS-LOOKUP|HANDOFF-RESULT|^SUMMARY:|^VERDICT|result:[[:space:]]*red' | cut -c1-400)"
    head12=""; [ "$dec" = none ] && head12="$(printf '%s\n' "$clean" | head -12 | cut -c1-300)"
    nxt="read the evidence file only for the lines above"
    case "$dec" in BLOCK) nxt="fix the FAIL/CONFIRMED items above, then run the independent role again on the new diff" ;; PASS) nxt="record via parse-verdict.sh --record (the envelope is not the verdict)" ;; esac
    body="ENVELOPE/1 role=$role decision=$dec dod_pass=$dp dod_fail=$df confirmed=$fc plausible=$fp blocking_severity=$crit evidence=$ref"
    [ -n "$keep" ] && body="$body"$'\n'"$keep"; [ -n "$head12" ] && body="$body"$'\n'"$head12"
    body="$body"$'\n'"NEXT: $nxt"
    shown="$(printf '%s\n' "$body" | wc -c | tr -d ' ')"
    printf '%s\n' "$body" | "$here/redact.sh"; echo "(bytes full=$fb shown=$shown; the envelope is a view, not a verdict: the verdict is parse-verdict.sh on the full answer)"
    note envelope "$fb" "$shown"; rm -f "$tmp" ;;
  stats)
    f="$top/$KIT_DIR/work/${slug:-_none}/context.jsonl"; [ -f "$f" ] || { echo "digest: no context.jsonl for ${slug:-_none}"; exit 0; }
    jq -rs 'group_by(.kind) | map({kind: .[0].kind, n: length, full: (map(.full_bytes) | add), shown: (map(.shown_bytes) | add)}) | .[] | "\(.kind): \(.n) view(s), full \(.full) bytes, shown \(.shown) bytes, kept off context \(.full - .shown) bytes"' "$f" ;;
  *) echo "usage: digest.sh output|envelope|stats ..." >&2; exit 2 ;;
esac
