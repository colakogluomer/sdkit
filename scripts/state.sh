#!/usr/bin/env bash
# Task state kept in a file so the orchestrator can resume after /clear, compaction or a crash, and so the
# "one automatic retry" rule is enforced by a script instead of by memory.
# State file: <project-dir>/work/<slug>/state.json (personal, gitignored).
#   state.sh <slug> init [risk] [branch]      create the file (keeps an existing one)
#   state.sh <slug> show                      print it
#   state.sh <slug> get <key>                 print a top-level value (step, risk, branch, verdict, ...)
#   state.sh <slug> set <key> <value>         set a top-level string value; `step` is the current workflow step
#   state.sh <slug> task <id> <status>        task status: todo|doing|done|blocked
#   state.sh <slug> retry <id>                exit 0 and count it the first time, exit 1 when the retry is already used
#   state.sh <slug> spawn                     count one subagent spawn; exit 1 once MAX_SPAWNS (sdkit.env, empty = no limit) is passed
#   state.sh <slug> path                      print the state file path
# Mutating commands take a lock (<state file>.lock), so parallel agents cannot lose each other's updates.
set -eu
command -v jq >/dev/null || { echo "state.sh needs jq" >&2; exit 1; }
top="$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$top"
slug="${1:-}"; cmd="${2:-}"
[ -n "$slug" ] && [ -n "$cmd" ] || { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "$slug" in *[!A-Za-z0-9_.-]*) echo "slug may contain letters, digits, _ . - only" >&2; exit 2 ;; esac
file="$top/$KIT_DIR/work/$slug/state.json"
# tele <type> [flags]: a telemetry event for this task (scripts/telemetry.sh); off unless TELEMETRY=1, and it can never fail a state command
tele() { [ "${TELEMETRY:-}" = 1 ] && [ -x "$(dirname "${BASH_SOURCE[0]}")/telemetry.sh" ] && { "$(dirname "${BASH_SOURCE[0]}")/telemetry.sh" emit "$@" --task "$slug" >/dev/null 2>&1 || true; }; return 0; }
need() { [ -f "$file" ] || { echo "no state for '$slug': run  state.sh $slug init" >&2; exit 1; }; }
write() { local tmp; tmp="$(mktemp "$file.XXXXXX")"; jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1 | .updated=\$now" "${@:2}" "$file" > "$tmp" && mv "$tmp" "$file"; rm -f "$tmp"; }
# every command that changes the file runs under one lock: parallel agents count spawns and set statuses at the same time
case "$cmd" in init|set|task|retry|spawn) sdkit_lock "$file"; trap 'sdkit_unlock "$file"' EXIT ;; esac

case "$cmd" in
  init)
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || jq -n --arg slug "$slug" --arg risk "${3:-}" --arg branch "${4:-}" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{slug:$slug, step:"0-intake", risk:$risk, branch:$branch, verdict:"", tasks:{}, retries:{}, updated:$now}' > "$file"
    echo "$file" ;;
  show) need; cat "$file" ;;
  path) echo "$file" ;;
  get) need; [ -n "${3:-}" ] || exit 2; jq -r --arg k "$3" '.[$k] // empty' "$file" ;;
  set)
    need; [ -n "${3:-}" ] || exit 2
    case "$3" in tasks|retries) echo "use the task/retry commands for $3" >&2; exit 2 ;; esac
    write '.[$k]=$v' --arg k "$3" --arg v "${4:-}" ;;
  task)
    need; [ -n "${3:-}" ] && [ -n "${4:-}" ] || exit 2
    case "$4" in todo|doing|done|blocked) ;; *) echo "status must be todo|doing|done|blocked" >&2; exit 2 ;; esac
    write '.tasks[$id]=$s' --arg id "$3" --arg s "$4" ;;
  retry)
    need; [ -n "${3:-}" ] || exit 2
    n="$(jq -r --arg id "$3" '.retries[$id] // 0' "$file")"
    if [ "$n" -ge 1 ]; then echo "retry for '$3' already used: stop and ask the user" >&2; tele failure --category verdict-block --source "retry-exhausted:$3"; exit 1; fi
    write '.retries[$id]=1' --arg id "$3"; tele retry --attempt 1 --source "$3" ;;
  spawn)
    need; n=$(( $(jq -r '.spawns // 0' "$file") + 1 ))
    write '.spawns=$n' --argjson n "$n"
    case "${MAX_SPAWNS:-}" in ''|*[!0-9]*|0) echo "spawns: $n"; exit 0 ;; esac
    if [ "$n" -gt "$MAX_SPAWNS" ]; then echo "spawn $n is over MAX_SPAWNS=$MAX_SPAWNS" >&2; exit 1; fi
    echo "spawns: $n of $MAX_SPAWNS" ;;
  *) echo "unknown command '$cmd'" >&2; exit 2 ;;
esac
