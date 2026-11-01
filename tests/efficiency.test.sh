#!/usr/bin/env bash
# F08 agent & verification efficiency: verdict normalisation, format vs semantic malformed, evidence-less PASS, early DoD check.
# Zero LLM cost, no network. Usage: tests/efficiency.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; PV="$ROOT/scripts/parse-verdict.sh"; DC="$ROOT/scripts/dod-check.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }
run() { "$@" > "$T/out" 2>&1; echo $?; }
V() { printf 'DOD\n%s\nFINDINGS\n%s\nVERIFY\n- command: v | result: green | ok\nVERDICT: %s\n' "$1" "$2" "$3"; }

echo "normalisation (shape only, never the judgement)"
printf 'Here is my answer:\n**DOD**\n* D1 a | pass | t.go:1\n2. D2 b | **PASS** | u.go:2\n**FINDINGS**\n- plausible | a.go:4 | maybe | x\n**VERIFY**\n- command: v | result: green | ok\n**VERDICT:** **PASS**\n' > "$T/n.txt"
eq "emphasis, bullets, lower-case tokens and a preamble parse" "$(run "$PV" "$T/n.txt")" 0
printf 'DOD\r\n- D1 a | PASS | t.go:1\r\nFINDINGS\r\n- none\r\nVERIFY\r\n- command: v | result: green | ok\r\nVERDICT: PASS\r\n' > "$T/crlf.txt"
eq "CRLF line ends parse" "$(run "$PV" "$T/crlf.txt")" 0
V '- D1 a | fail | t.go:1' '- none' block > "$T/f.txt"
eq "a lower-case fail still blocks" "$(run "$PV" "$T/f.txt")" 1
V '- D1 a | PASS | t.go:1' '- none' maybe > "$T/m.txt"
eq "an unknown verdict word is not guessed" "$(run "$PV" "$T/m.txt")" 2
eq "…and is a format error" "$(grep -c 'MALFORMED\[format\]' "$T/out")" 1

echo "semantic errors are never repaired"
V '- D1 a | FAIL | t.go:1' '- none' PASS > "$T/s1.txt"
eq "PASS with a FAIL item is refused" "$(run "$PV" "$T/s1.txt")" 2
eq "…as semantic" "$(grep -c 'MALFORMED\[semantic\]' "$T/out")" 1
V '- D1 a | PASS | t.go:1' '- CONFIRMED | a.go:4 | bad | x' PASS > "$T/s2.txt"
eq "PASS with a CONFIRMED finding is refused" "$(run "$PV" "$T/s2.txt")" 2
for ev in manual post-deploy n/a pending ""; do
  V "- D1 a | PASS | $ev" '- none' PASS > "$T/e.txt"
  eq "PASS with evidence '$ev' is refused" "$(run "$PV" "$T/e.txt")" 2
  eq "…as semantic ('$ev')" "$(grep -c 'MALFORMED\[semantic\]' "$T/out")" 1
done
V '- D1 a | FAIL | manual check not done' '- none' BLOCK > "$T/e2.txt"
eq "a manual item recorded as FAIL blocks (not a pass)" "$(run "$PV" "$T/e2.txt")" 1
printf 'SUMMARY: 1 blockers, 0 major, 0 minor\nVERDICT: PASS\n' > "$T/r.txt"
eq "reviewer: counts without the finding are semantic" "$(run "$PV" "$T/r.txt" --role reviewer)" 2
eq "…" "$(grep -c 'MALFORMED\[semantic\]' "$T/out")" 1
printf 'VERDICT: PASS\n' > "$T/r2.txt"
eq "reviewer: a missing SUMMARY is a format error" "$(run "$PV" "$T/r2.txt" --role reviewer)" 2
eq "…" "$(grep -c 'MALFORMED\[format\]' "$T/out")" 1

echo "early DoD check"
printf '## Definition of Done\n- D1: a | Verified by: unit test\n- D2: b | Verified by: manual check\n- D3: c | Verified by: none: doc only\n- D4: d | Verified by: post-deploy smoke\n- D5: e | Verified by: lint\n' > "$T/ok.md"
eq "a classified DoD is ok" "$(run "$DC" "$T/ok.md")" 0
eq "…with counts" "$(grep -c 'automated=1 static=1 manual=1 post-deploy=1 none=1' "$T/out")" 1
eq "…and the evidence reminder" "$(grep -c '^note:' "$T/out")" 1
printf '## Definition of Done\n- D1: a | Verified by: unit test\n- D1: dup | Verified by: lint\n- D2: x\n- D3: y | Verified by: none\n- D4: z | Verified by: vibes\n' > "$T/bad.md"
eq "problems exit 1" "$(run "$DC" "$T/bad.md")" 1
eq "duplicate id named" "$(grep -c 'duplicate id D1' "$T/out")" 1
eq "missing method named" "$(grep -c 'D2: no' "$T/out")" 1
eq "bare none named" "$(grep -c 'D3.*needs a reason' "$T/out")" 1
eq "an unclassified method is only a warning, counted as manual" "$(grep -c 'warn: D4: unclassified method' "$T/out")" 1
printf '# nothing\n' > "$T/none.md"
eq "no items is a problem" "$(run "$DC" "$T/none.md")" 1
eq "a missing file is a usage error" "$(run "$DC" "$T/absent.md")" 2

echo "efficiency: $pass passed, $failed failed"
[ "$failed" = 0 ]
