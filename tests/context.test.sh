#!/usr/bin/env bash
# F09 context optimisation: bounded views keep every failure line and the full text on disk; the envelope is a view, never a verdict.
# Zero LLM cost. Reduction numbers below are fixture bytes (characters), not tokens and not a live measurement.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DG="$ROOT/scripts/digest.sh"; PV="$ROOT/scripts/parse-verdict.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; export CLAUDE_PROJECT_DIR="$T/proj"; mkdir -p "$T/proj/.sdkit"; : > "$T/proj/.sdkit/sdkit.env"
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }

echo "tool output"
seq 1 40 | "$DG" output --max 60 > "$T/short.out"
eq "a short output passes through unchanged" "$(cat "$T/short.out" | wc -l | tr -d ' ')" 40
seq 1 500 | sed '120s/.*/FAIL: test_a broke/; 333s/.*/panic: nil map/' | "$DG" output --max 60 --ref "$T/full.txt" > "$T/long.out"
eq "a long output is bounded"                 "$([ "$(wc -l < "$T/long.out")" -lt 60 ] && echo yes)" yes
eq "the first failure line is kept"          "$(grep -c '120:FAIL: test_a broke' "$T/long.out")" 1
eq "the second failure line is kept"         "$(grep -c '333:panic: nil map' "$T/long.out")" 1
eq "the full text is retrievable, identical" "$(seq 1 500 | sed '120s/.*/FAIL: test_a broke/; 333s/.*/panic: nil map/' | cmp -s - "$T/full.txt" && echo same)" same
eq "the view names the path"                 "$(grep -c "the full text is in $T/full.txt" "$T/long.out")" 1
seq 1 500 | sed 's/^\(.*\)$/FAIL: case \1/' | "$DG" output --max 60 --ref "$T/f2.txt" > "$T/many.out"
eq "many failures: capped (80 + head + tail), still has the pointer" "$([ "$(grep -c 'FAIL: case' "$T/many.out")" -le 110 ] && grep -c 'f2.txt' "$T/many.out")" 1

echo "role envelope"
{ echo DOD; for i in $(seq 1 30); do echo "- D$i behaviour number $i is covered by the unit test in pkg/module_$i/handler_test.go | PASS | handler_test.go:$i the table-driven case asserts the exact error and the retry count"; done
  echo "- D31 last item | FAIL | no test exercises it"; echo FINDINGS; echo "- CONFIRMED | svc/a.go:44 | unchecked error | the write fails silently"; echo "- PLAUSIBLE | svc/b.go:9 | maybe racy | two writers"
  echo VERIFY; echo "- command: verify.sh | result: red | 1 failing test"; echo "VERDICT: BLOCK"; } > "$T/big.txt"
"$DG" envelope --role verifier --file "$T/big.txt" --ref "$T/ev.md" > "$T/env.out"
eq "decision is BLOCK"                        "$(head -1 "$T/env.out" | grep -c 'decision=BLOCK')" 1
eq "counts: 30 pass, 1 fail, 1 confirmed"     "$(head -1 "$T/env.out" | grep -c 'dod_pass=30 dod_fail=1 confirmed=1 plausible=1')" 1
eq "the FAIL line is verbatim"                "$(grep -c '^- D31 last item | FAIL | no test exercises it' "$T/env.out")" 1
eq "the CONFIRMED line is verbatim"           "$(grep -c '^- CONFIRMED | svc/a.go:44 | unchecked error | the write fails silently' "$T/env.out")" 1
eq "the full answer is stored unchanged"      "$(cmp -s "$T/big.txt" "$T/ev.md" && echo same)" same
eq "the evidence path is named"               "$(head -1 "$T/env.out" | grep -c "evidence=$T/ev.md")" 1
full=$(wc -c < "$T/big.txt" | tr -d ' '); shown=$(wc -c < "$T/env.out" | tr -d ' ')
eq "the envelope is smaller than the answer (fixture bytes: $full -> $shown)" "$([ "$shown" -lt "$full" ] && echo yes)" yes
eq "the verdict still comes from the full answer" "$("$PV" "$T/ev.md" >/dev/null 2>&1; echo $?)" 1
printf 'DOD\n- D1 a | PASS | t.go:1\nFINDINGS\n- none\nVERIFY\n- command: v | result: green | ok\nVERDICT: PASS\n' > "$T/small.txt"
eq "a short answer is printed unchanged"      "$("$DG" envelope --role verifier --file "$T/small.txt" --ref "$T/e2.md" | cmp -s - "$T/small.txt" && echo same)" same
{ for i in $(seq 1 60); do echo "- BLOCKER | a.go:$i | issue $i with a long explanation of the problem and how it fails in practice | scenario"; done; echo "SUMMARY: 60 blockers, 0 major, 0 minor"; echo "VERDICT: BLOCK"; } > "$T/rev.txt"
"$DG" envelope --role reviewer --file "$T/rev.txt" --ref "$T/rev.md" > "$T/rev.out"
eq "reviewer: every BLOCKER line survives"    "$(grep -c '^- BLOCKER' "$T/rev.out")" 60
printf 'I looked around.\n%s\nNEEDS-LOOKUP: where is X defined?\n' "$(seq 1 300 | sed 's/^/ordinary prose line /')" > "$T/free.txt"
"$DG" envelope --role developer --file "$T/free.txt" --ref "$T/free.md" > "$T/free.out"
eq "free-form: bounded, NEEDS-LOOKUP kept"    "$(grep -c '^NEEDS-LOOKUP' "$T/free.out")$([ "$(wc -l < "$T/free.out")" -lt 30 ] && echo ok)" 1ok
eq "a missing --role is a usage error"        "$("$DG" envelope --file "$T/big.txt" >/dev/null 2>&1; echo $?)" 2

echo "instrumentation"
st="$("$DG" stats 2>&1)"
eq "stats count the views"                    "$(printf '%s\n' "$st" | grep -c 'envelope: .* view(s)')" 1
eq "stats report bytes kept off context"      "$(printf '%s\n' "$st" | grep -c 'kept off context')" 2
eq "DIGEST_STATS=0 writes nothing more"       "$(n=$(wc -l < "$T/proj/.sdkit/work/_none/context.jsonl"); DIGEST_STATS=0 "$DG" envelope --role verifier --file "$T/big.txt" --ref "$T/e3.md" >/dev/null; echo $(( $(wc -l < "$T/proj/.sdkit/work/_none/context.jsonl") - n )))" 0

echo "run-role accepts --envelope"
printf 'ROLE: verifier\nTASK: x\n' > "$T/h.md"
eq "dry run with --envelope"                  "$("$ROOT/scripts/run-role.sh" verifier --handoff "$T/h.md" --cwd "$T" --host claude --dry-run --envelope >/dev/null 2>&1; echo $?)" 0

echo "context: $pass passed, $failed failed"
[ "$failed" = 0 ]
