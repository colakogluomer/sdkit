#!/usr/bin/env bash
# Cheap, risk-based PR checks for the kit itself or a repo that vendors it (F20): what a pull request must pass WITHOUT a full-suite run.
#   pr-check.sh [--base REF] [--list] [--milestone]
#   T0 (always, seconds): bash -n on changed *.sh, jq on changed *.json, build-adapters.sh --check, audit.sh policy
#   T1 (always): the suites test-select.sh maps to the changed files (tests/test-map.conf); an unmapped or shared file runs everything (conservative)
#   --milestone: T3, the full suite from the map's @all line, plus the fixture-benchmark regression check (bench/history.sh check). Release / milestone
#                boundaries only. Paid benchmarks are never started here (tier T4 needs an explicit decision).
#   --list: print the plan, run nothing.
# Prints one line per step with its elapsed seconds and a final summary; the exit status is 1 if any step failed (nothing is hidden behind a pipe).
# Exit: 0 all green, 1 a step failed, 2 usage.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "pr-check needs a git repository" >&2; exit 2; }
base=""; list=0; mile=0
while [ $# -gt 0 ]; do case "$1" in --base) base="$2"; shift ;; --list) list=1 ;; --milestone) mile=1 ;; *) echo "usage: pr-check.sh [--base REF] [--list] [--milestone]" >&2; exit 2 ;; esac; shift; done
cd "$top" || exit 2
if [ -z "$base" ]; then for c in origin/main origin/master main master HEAD; do git rev-parse --verify -q "$c" >/dev/null && { base="$c"; break; }; done; fi
mb="$(git merge-base "$base" HEAD 2>/dev/null || echo HEAD)"
changed="$( { git diff --name-only "$mb"; git ls-files -o --exclude-standard; } | sort -u)"
sh_files="$(printf '%s\n' "$changed" | grep -E '\.sh$' | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done)"
json_files="$(printf '%s\n' "$changed" | grep -E '\.json$' | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done)"
if [ "$list" = 1 ]; then
  echo "base $base (merge-base $(printf '%s' "$mb" | cut -c1-8)), $(printf '%s\n' "$changed" | awk 'NF' | wc -l | tr -d ' ') changed file(s)"
  echo "T0: bash -n x$(printf '%s\n' "$sh_files" | awk 'NF' | wc -l | tr -d ' '), jq x$(printf '%s\n' "$json_files" | awk 'NF' | wc -l | tr -d ' '), build-adapters --check, audit policy"
  echo "T1:"; "$here/test-select.sh" list --base "$mb" | sed 's/^/  /'
  [ "$mile" = 1 ] && echo "T3: full suite + bench/history.sh check"; exit 0
fi
fails=0; t_all=$(date +%s)
step() {  # step <label> <command...>
  local l="$1"; shift; local s=$(date +%s)
  if "$@" > "${TMPDIR:-/tmp}/pr-check.$$.log" 2>&1; then echo "ok    $l ($(( $(date +%s) - s ))s)"
  else echo "FAIL  $l ($(( $(date +%s) - s ))s)"; tail -15 "${TMPDIR:-/tmp}/pr-check.$$.log" | sed 's/^/      /'; fails=$((fails + 1)); fi; rm -f "${TMPDIR:-/tmp}/pr-check.$$.log"; }
syntax() { local f rc=0; for f in $sh_files; do bash -n "$f" || rc=1; done; return $rc; }
jsonok() { local f rc=0; for f in $json_files; do jq . "$f" >/dev/null || { echo "$f"; rc=1; }; done; return $rc; }
step "T0 bash -n ($(printf '%s\n' "$sh_files" | awk 'NF' | wc -l | tr -d ' ') files)" syntax
step "T0 jq ($(printf '%s\n' "$json_files" | awk 'NF' | wc -l | tr -d ' ') files)" jsonok
[ -x "$here/../bin/build-adapters.sh" ] && step "T0 adapters are generated from core/roles" "$here/../bin/build-adapters.sh" --check
[ -x "$here/audit.sh" ] && step "T0 shipped enforcement (audit policy)" "$here/audit.sh" policy
if [ "$mile" = 1 ]; then
  step "T3 full suite (milestone)" "$here/test-select.sh" run --tier T3 --files tests/test-map.conf --no-cache
  [ -x "$top/bench/history.sh" ] && step "T3 fixture benchmark regression" "$top/bench/history.sh" check
else
  step "T1 focused suites for the changed files" "$here/test-select.sh" run --base "$mb"
fi
echo "pr-check: $([ "$fails" = 0 ] && echo green || echo "$fails step(s) FAILED"), $(( $(date +%s) - t_all ))s total; tier $([ "$mile" = 1 ] && echo T3 || echo T1) (a green T1 is not a full regression)"
[ "$fails" = 0 ]
