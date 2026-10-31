#!/usr/bin/env bash
# Deterministic plan <-> proposal <-> tasks comparison (replaces an LLM eyeball check).
# Usage: check-plan-parity.sh <plan.md> <proposal.md> [tasks.md] [--loose]
#   DoD items are lines of the form   D<n>: <text> | Verified by: <type>   (also "- D1." / "**D1**:"), read from the
#   "Definition of Done" section of each file (the whole file when it has no such heading).
#   Default: id, text and Verified-by must match after normalisation. --loose: ids and Verified-by only.
#   With tasks.md: the task lines (`- [ ] T3 ... | role: | writes: | after:`) of plan.md section "Execution plan"
#   (or the whole file) must match tasks.md on id, role, writes and after (status ignored).
# Exit 0 equal, 1 differences (printed), 2 usage / no DoD items found.
set -u
plan="${1:-}"; prop="${2:-}"; tasks=""; loose=0
shift 2 2>/dev/null || true
for a in "$@"; do case "$a" in --loose) loose=1 ;; *) tasks="$a" ;; esac; done
[ -f "$plan" ] && [ -f "$prop" ] || { echo "usage: check-plan-parity.sh plan.md proposal.md [tasks.md] [--loose]" >&2; exit 2; }

section() { # <file> <heading regex>: lines of the section, or the whole file when absent
  local out; out="$(awk -v re="$2" 'BEGIN{IGNORECASE=1} /^#+[ \t]/ { if (inside) exit; if (tolower($0) ~ re) { inside=1; next } } inside { print }' "$1")"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else cat "$1"; fi
}
dod_items() { # <file>: "D<n>\t<text>\t<verified-by>" per item
  section "$1" 'definition of done' | awk '
    function norm(s) { gsub(/[*_`|]/, " ", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/[ .;,:—–-]+$/, "", s); return s }
    match($0, /^[ \t]*([-*][ \t]+)?[*_]*D[0-9]+[*_]*[.:)]/) {
      head = substr($0, 1, RLENGTH); rest = tolower(substr($0, RLENGTH + 1))
      id = head; sub(/^[^D]*D/, "", id); sub(/[^0-9].*$/, "", id)
      vb = ""; text = rest
      if (match(rest, /verified by:?[ \t*_]*/)) { vb = substr(rest, RSTART + RLENGTH); text = substr(rest, 1, RSTART - 1) }
      printf "D%s\t%s\t%s\n", id, norm(text), norm(vb)
    }'
}
task_lines() { # <file>: "T<id>\t<role>|<writes>|<after>"
  section "$1" 'execution plan' | awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*- \[[ xX]\] +[A-Za-z0-9_.-]+/ {
      line = $0; sub(/^[ \t]*- \[[ xX]\] +/, "", line)
      n = split(line, f, "|"); split(trim(f[1]), h, " "); r = ""; w = ""; a = ""
      for (k = 2; k <= n; k++) { kv = trim(f[k])
        if (kv ~ /^role:/) { sub(/^role:[ ]*/, "", kv); r = kv } else if (kv ~ /^writes:/) { sub(/^writes:[ ]*/, "", kv); w = kv } else if (kv ~ /^after:/) { sub(/^after:[ ]*/, "", kv); a = kv } }
      gsub(/[ \t]/, "", w); gsub(/[ \t]/, "", a); printf "%s\t%s|%s|%s\n", h[1], r, w, a
    }' | sort
}

rc=0
a="$(dod_items "$plan" | sort)"; b="$(dod_items "$prop" | sort)"
[ -n "$a" ] || { echo "no DoD items (D<n>: ...) found in $plan" >&2; exit 2; }
[ -n "$b" ] || { echo "no DoD items (D<n>: ...) found in $prop" >&2; exit 2; }
if [ "$loose" = 1 ]; then a="$(printf '%s\n' "$a" | awk -F'\t' '{print $1 "\t\t" $3}')"; b="$(printf '%s\n' "$b" | awk -F'\t' '{print $1 "\t\t" $3}')"; fi
if ! diff_out="$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"; then
  echo "DoD differs (< plan, > proposal):"; printf '%s\n' "$diff_out" | grep '^[<>]' | tr '\t' '|' | sed 's/^/  /'; rc=1
fi
if [ -n "$tasks" ]; then
  [ -f "$tasks" ] || { echo "tasks file not found: $tasks" >&2; exit 2; }
  ta="$(task_lines "$plan")"; tb="$(task_lines "$tasks")"
  if ! diff_out="$(diff <(printf '%s\n' "$ta") <(printf '%s\n' "$tb"))"; then
    echo "tasks differ (< plan, > tasks.md):"; printf '%s\n' "$diff_out" | grep '^[<>]' | tr '\t' '|' | sed 's/^/  /'; rc=1
  fi
fi
[ "$rc" = 0 ] && echo "parity ok: $(printf '%s\n' "$a" | wc -l | tr -d ' ') DoD item(s)${tasks:+, tasks match}"
exit "$rc"
