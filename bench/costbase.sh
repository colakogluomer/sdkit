#!/usr/bin/env bash
# F11 zero-cost baseline: deterministic fixture metrics for the F08 (format reruns), F09 (context bytes) and F10 (suites per small patch) levers,
# captured as machine-readable JSON, plus a guarded compare. NO model is called, so nothing here is a dollar figure or a token count:
# "cost per accepted task" needs live runs (tier T4, explicit approval) and is reported as NOT MEASURED.
#   bench/costbase.sh capture <label> [--out DIR]    writes DIR/<label>.costbase.json (default bench/baselines)
#   bench/costbase.sh compare A.json B.json          deltas; refuses when schema or fixture set differ
# Arms: verdict normalisation off (PARSE_NORMALIZE=0, the pre-F08 parser) vs on; full vs bounded view; full suite vs selected suites.
# Sample size is the fixture count, the result is deterministic (uncertainty 0 for the fixtures, unknown for real traffic).
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"; cmd="${1:-}"; shift 2>/dev/null || true
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
case "$cmd" in
capture)
  label="${1:-}"; [ -n "$label" ] || { echo "usage: costbase.sh capture <label> [--out DIR]" >&2; exit 2; }; shift; out="$KIT/bench/baselines"
  [ "${1:-}" = --out ] && out="$2"; mkdir -p "$out"
  PV="$KIT/scripts/parse-verdict.sh"
  mk() { printf 'DOD\n%s\nFINDINGS\n%s\nVERIFY\n- command: v | result: green | ok\nVERDICT: %s\n' "$2" "$3" "$4" > "$T/v-$1.txt"; }
  # format-only variants (same judgement as the clean one; a rerun is pure waste) ...
  mk clean '- D1 a | PASS | t.go:1' '- none' PASS
  mk lower '- D1 a | pass | t.go:1' '- none' PASS
  mk bold '- D1 a | **PASS** | t.go:1' '- none' PASS
  mk star '* D1 a | PASS | t.go:1' '- none' PASS
  mk numbered '1. D1 a | PASS | t.go:1' '- none' PASS
  mk lowerfind '- D1 a | PASS | t.go:1' '- plausible | a.go:1 | x | y' PASS
  printf 'DOD\r\n- D1 a | PASS | t.go:1\r\nFINDINGS\r\n- none\r\nVERIFY\r\n- command: v | result: green | ok\r\nVERDICT: PASS\r\n' > "$T/v-crlf.txt"
  sed 's/^VERDICT: PASS/**VERDICT:** **PASS**/' "$T/v-clean.txt" > "$T/v-boldverdict.txt"
  fmt_n=8
  # ... and judgements that must NEVER be accepted, with normalisation on or off
  mk failpass '- D1 a | FAIL | t.go:1' '- none' PASS
  mk manualpass '- D1 a | PASS | manual' '- none' PASS
  mk confpass '- D1 a | PASS | t.go:1' '- CONFIRMED | a.go:1 | x | y' PASS
  sem_n=3
  arm() {  # <PARSE_NORMALIZE> <names...>: prints accepted-count (exit 0 or 1 = well-formed)
    local n="$1" ok=0; shift; for v in "$@"; do PARSE_NORMALIZE="$n" "$PV" "$T/v-$v.txt" >/dev/null 2>&1; case $? in 0|1) ok=$((ok + 1)) ;; esac; done; echo "$ok"; }
  fmtv="clean lower bold star numbered lowerfind crlf boldverdict"; semv="failpass manualpass confpass"
  off_ok=$(arm 0 $fmtv); on_ok=$(arm 1 $fmtv); sem_off=$(arm 0 $semv); sem_on=$(arm 1 $semv)
  # context: bounded view of fixture outputs (bytes = characters)
  export CLAUDE_PROJECT_DIR="$T/p"; mkdir -p "$T/p/.sdkit"; : > "$T/p/.sdkit/sdkit.env"; export DIGEST_STATS=0
  seq 1 2000 | sed '700s/.*/FAIL: test_x broke/; 1500s/.*/panic: nil/' > "$T/o1.txt"
  { echo DOD; for i in $(seq 1 30); do echo "- D$i behaviour $i is covered by the unit test in pkg/m_$i/handler_test.go | PASS | handler_test.go:$i table-driven case asserts the exact error"; done
    echo "- D31 x | FAIL | no test"; echo FINDINGS; echo "- CONFIRMED | a.go:4 | unchecked | silent"; echo VERIFY; echo "- command: v | result: red | 1"; echo "VERDICT: BLOCK"; } > "$T/o2.txt"
  f1=$(wc -c < "$T/o1.txt"); s1=$("$KIT/scripts/digest.sh" output --ref "$T/r1" < "$T/o1.txt" | wc -c)
  f2=$(wc -c < "$T/o2.txt"); s2=$("$KIT/scripts/digest.sh" envelope --role verifier --file "$T/o2.txt" --ref "$T/r2" | wc -c)
  kept=$("$KIT/scripts/digest.sh" output --ref "$T/r1" < "$T/o1.txt" | grep -c 'FAIL: test_x broke\|panic: nil')
  # tests: suites per small patch, with the kit's own map
  cd "$KIT" || exit 1; full=$("$KIT/scripts/test-select.sh" list --tier T3 --files tests/test-map.conf | grep -vc '^#')
  patches=""; tot_sel=0; n=0
  for f in scripts/route.sh scripts/usage.sh scripts/parse-verdict.sh scripts/digest.sh docs/guide.md; do
    c=$("$KIT/scripts/test-select.sh" list --files "$f" | grep -vc '^#'); case "$("$KIT/scripts/test-select.sh" list --files "$f" | head -1)" in tests:*) c=0 ;; esac
    patches="$patches{\"file\":\"$f\",\"suites\":$c},"; tot_sel=$((tot_sel + c)); n=$((n + 1))
  done
  git_head=$(git rev-parse --short HEAD 2>/dev/null || echo unknown); dirty=$(git status --porcelain 2>/dev/null | grep -c . || true)
  fx=$(cat "$T"/v-*.txt "$T/o1.txt" "$T/o2.txt" | shasum | cut -d' ' -f1); mapsha=$(shasum < "$KIT/tests/test-map.conf" | cut -d' ' -f1)
  jq -n --arg label "$label" --arg head "$git_head" --argjson dirty "$dirty" --arg fx "$fx" --arg ms "$mapsha" \
    --argjson fn "$fmt_n" --argjson off "$off_ok" --argjson on "$on_ok" --argjson sn "$sem_n" --argjson soff "$sem_off" --argjson son "$sem_on" \
    --argjson f1 "$f1" --argjson s1 "$s1" --argjson f2 "$f2" --argjson s2 "$s2" --argjson kept "$kept" --argjson full "$full" --argjson totsel "$tot_sel" --argjson np "$n" \
    --argjson patches "[${patches%,}]" '{
    schema: "costbase/1", label: $label, mode: "fixture", model_calls: 0, git: {head: $head, dirty_files: $dirty}, fixture_sha: ($fx + ":" + $ms),
    verdict_format: {format_only_variants: $fn, accepted_first_try_without_normalization: $off, accepted_first_try_with_normalization: $on,
                     avoidable_reruns_without: ($fn - $off), avoidable_reruns_with: ($fn - $on),
                     semantic_cases: $sn, wrongly_accepted_without: $soff, wrongly_accepted_with: $son},
    context: {tool_output: {full_bytes: $f1, shown_bytes: $s1, failure_lines_kept_of_2: $kept}, role_answer: {full_bytes: $f2, shown_bytes: $s2},
              unit: "characters, not tokens"},
    tests: {full_suites: $full, small_patches: $patches, mean_selected_suites: ($totsel / $np)},
    cost_per_accepted_task: "NOT MEASURED (needs live runs, tier T4, not authorised)",
    limits: ["fixtures, not real traffic", "bytes are not tokens", "suite counts are not wall time", "n = fixture count, deterministic"]}' > "$out/$label.costbase.json"
  echo "wrote $out/$label.costbase.json"; jq -c '{verdict_format, context, tests: {full_suites: .tests.full_suites, mean_selected_suites: .tests.mean_selected_suites}}' "$out/$label.costbase.json" ;;
compare)
  a="${1:-}"; b="${2:-}"; [ -f "$a" ] && [ -f "$b" ] || { echo "usage: costbase.sh compare A.json B.json" >&2; exit 2; }
  [ "$(jq -r .schema "$a")" = "$(jq -r .schema "$b")" ] || { echo "refused: different schema" >&2; exit 3; }
  [ "$(jq -r .fixture_sha "$a")" = "$(jq -r .fixture_sha "$b")" ] || { echo "refused: different fixture set or test map; the numbers are not comparable" >&2; exit 3; }
  jq -n --slurpfile a "$a" --slurpfile b "$b" '$a[0] as $x | $b[0] as $y | {from: $x.label, to: $y.label,
    avoidable_format_reruns: [$x.verdict_format.avoidable_reruns_with, $y.verdict_format.avoidable_reruns_with],
    wrongly_accepted_semantic: [$x.verdict_format.wrongly_accepted_with, $y.verdict_format.wrongly_accepted_with],
    shown_bytes_tool_output: [$x.context.tool_output.shown_bytes, $y.context.tool_output.shown_bytes],
    mean_selected_suites: [$x.tests.mean_selected_suites, $y.tests.mean_selected_suites],
    cost_per_accepted_task: "NOT MEASURED"}' ;;
*) echo "usage: costbase.sh capture <label> [--out DIR] | compare A B" >&2; exit 2 ;;
esac
