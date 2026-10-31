#!/usr/bin/env bash
# Token ledger: one JSON line per agent run, so cost can be measured instead of guessed. Off unless USAGE_LOG=1 in sdkit.env
# (log is then a silent no-op). File: <project-dir>/work/<slug>/usage.jsonl (personal, gitignored).
#   usage.sh log --role R [--tier T] [--host H] [--model M] [--in N] [--out N] [--cache-read N] [--cache-write N]
#                [--slug S] [--id ID] [--source X] [--tq actual|unavailable] [--force]
#       --tq unavailable marks a run whose host printed no token usage: its in/out/cache fields are 0 only because nothing was read, not because nothing was used
#       (route.sh counts such runs as unmeasured, never as zero)
#       --id makes the line replace an earlier line with the same id (snapshots of a growing session)
#       --force logs even when USAGE_LOG is not 1
#   usage.sh report [slug]      totals per role and tier, then a grand total and the cache hit rate (all slugs when none is given)
#   usage.sh budget [slug]      used vs TOKEN_BUDGET_TASK (in + out + cache-write; cache reads are cheap and left out).
#                               Exit 0 under TOKEN_BUDGET_WARN_PCT (default 70), 3 from there, 4 at 100%. Silent exit 0 when no budget or no data.
# Slug default: the task the phase machine has open (sdd.sh task), else the most recently updated work/<slug>/state.json, else "_misc".
set -u
command -v jq >/dev/null || { echo "usage.sh needs jq" >&2; exit 1; }
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$top"
work="$top/$KIT_DIR/work"

current_slug() {  # the open SDD task, else the most recently updated work/*/state.json, else _misc
  local s; s="$(sdkit_active_slug "$top")"
  echo "${s:-_misc}"
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  log)
    role=""; tier=""; host=""; model=""; tin=0; tout=0; cr=0; cw=0; slug=""; id=""; source=""; force=0; tq=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --role) role="$2"; shift ;; --tier) tier="$2"; shift ;; --host) host="$2"; shift ;; --model) model="$2"; shift ;;
        --in) tin="$2"; shift ;; --out) tout="$2"; shift ;; --cache-read) cr="$2"; shift ;; --cache-write) cw="$2"; shift ;;
        --slug) slug="$2"; shift ;; --id) id="$2"; shift ;; --source) source="$2"; shift ;; --tq) tq="$2"; shift ;; --force) force=1 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
      esac
      shift
    done
    [ "${USAGE_LOG:-}" = 1 ] || [ "$force" = 1 ] || exit 0
    [ -n "$role" ] || { echo "--role is required" >&2; exit 2; }
    [ -n "$slug" ] || slug="$(current_slug)"
    mkdir -p "$work/$slug"; file="$work/$slug/usage.jsonl"
    line="$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg role "$role" --arg tier "$tier" --arg host "$host" --arg model "$model" \
      --arg id "$id" --arg source "$source" --arg tq "$tq" --argjson i "${tin:-0}" --argjson o "${tout:-0}" --argjson cr "${cr:-0}" --argjson cw "${cw:-0}" \
      '{ts:$ts, role:$role, tier:$tier, host:$host, model:$model, id:$id, source:$source, in:$i, out:$o, cache_read:$cr, cache_write:$cw} + (if $tq != "" then {tq:$tq} else {} end)')"
    # agents finish at the same time: the replace-then-append runs under a lock, or lines of parallel agents are lost
    sdkit_lock "$file"
    if [ -n "$id" ] && [ -f "$file" ]; then
      grep -vF "\"id\":\"$id\"" "$file" > "$file.tmp.$$" || true; mv "$file.tmp.$$" "$file"
    fi
    printf '%s\n' "$line" >> "$file"
    sdkit_unlock "$file" ;;
  report)
    slug="${1:-}"
    if [ -n "$slug" ]; then files="$work/$slug/usage.jsonl"; else files="$(ls "$work"/*/usage.jsonl 2>/dev/null)"; fi
    [ -n "$files" ] && cat $files 2>/dev/null | grep -q . || { echo "no usage recorded (set USAGE_LOG=1 in sdkit.env)"; exit 0; }
    # shellcheck disable=SC2086
    cat $files | jq -rs '
      map(.tier |= (if . == "" then "-" else . end)) |
      "role\ttier\truns\tin\tout\tcache_read\tcache_write",
      (group_by([.role,.tier]) | map("\(.[0].role)\t\(.[0].tier)\t\(length)\t\(map(.in)|add)\t\(map(.out)|add)\t\(map(.cache_read)|add)\t\(map(.cache_write)|add)") | .[]),
      "TOTAL\t-\t\(length)\t\(map(.in)|add)\t\(map(.out)|add)\t\(map(.cache_read)|add)\t\(map(.cache_write)|add)"' | column -t -s "$(printf '\t')"
    cat $files | jq -rs 'map(select(.tq == "unavailable")) | length as $n | if $n > 0 then "\($n) run(s) reported no token usage: their zeros above are unmeasured, not counted usage" else empty end'
    # share of input served from the prompt cache: cache_read / (in + cache_read + cache_write)
    cat $files | jq -rs '(map(.in)|add) as $i | (map(.cache_read)|add) as $r | (map(.cache_write)|add) as $w
      | if ($i + $r + $w) > 0 then "cache hit rate: \(($r * 100 / ($i + $r + $w)) | floor)%" else empty end' ;;
  budget)
    slug="${1:-}"; [ -n "$slug" ] || slug="$(current_slug)"
    case "${TOKEN_BUDGET_TASK:-}" in ''|*[!0-9]*|0) exit 0 ;; esac
    file="$work/$slug/usage.jsonl"; [ -f "$file" ] || exit 0
    used="$(jq -rs 'map(.in + .out + .cache_write) | add // 0' "$file")"
    warn="${TOKEN_BUDGET_WARN_PCT:-70}"; case "$warn" in ''|*[!0-9]*) warn=70 ;; esac
    pct=$(( used * 100 / TOKEN_BUDGET_TASK ))
    echo "token budget for $slug: $used of $TOKEN_BUDGET_TASK used (${pct}%)"
    [ "$pct" -ge 100 ] && exit 4
    [ "$pct" -ge "$warn" ] && exit 3
    exit 0 ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
