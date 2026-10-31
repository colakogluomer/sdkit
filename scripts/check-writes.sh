#!/usr/bin/env bash
# Fail when a task changed files outside its `writes:` set (tasks.md line: `- [ ] T3 ... | writes: a/,b.go | ...`).
# Usage: check-writes.sh <tasks.md> <task-id> <base-ref> [head-ref]
#   With head-ref: committed changes base..head. Without: base..working tree plus untracked files (run it inside the task's worktree).
#   A task with no `writes:` is read-only: any change fails. Exit 0 ok, 1 out-of-scope files (listed), 2 usage / unknown task.
set -u
tasks="${1:-}"; id="${2:-}"; base="${3:-}"; head="${4:-}"
[ -f "$tasks" ] && [ -n "$id" ] && [ -n "$base" ] || { echo "usage: check-writes.sh tasks.md task-id base-ref [head-ref]" >&2; exit 2; }
line="$(grep -E "^[[:space:]]*- \[[ xX]\] +$id([[:space:]|]|\$)" "$tasks" | head -1)"
[ -n "$line" ] || { echo "task $id not found in $tasks" >&2; exit 2; }
writes="$(printf '%s' "$line" | tr '|' '\n' | sed -n 's/^[[:space:]]*writes:[[:space:]]*//p' | tr -d ' ')"
if [ -n "$head" ]; then changed="$(git diff --name-only "$base" "$head")"
else changed="$( { git diff --name-only "$base"; git ls-files -o --exclude-standard; } | sort -u)"; fi
[ -n "$changed" ] || exit 0
bad=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  ok=0
  IFS=',' read -r -a ps <<< "$writes"
  for p in "${ps[@]:-}"; do
    [ -z "$p" ] && continue; p="${p%/}"
    if [ "$f" = "$p" ] || [ "${f#"$p"/}" != "$f" ]; then ok=1; break; fi
  done
  [ "$ok" = 1 ] || bad="$bad  $f"$'\n'
done <<< "$changed"
if [ -n "$bad" ]; then echo "task $id changed files outside writes: [${writes:-none}]:"; printf '%s' "$bad"; exit 1; fi
