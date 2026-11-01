#!/usr/bin/env bash
# F17 trace: a failed task is explained from ids, roles, numbers and reason codes; no note/prompt/answer text appears. No model.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"; TL="$KIT/scripts/telemetry.sh"; US="$KIT/scripts/usage.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }
R="$T/r"; mkdir -p "$R/.sdkit"; cd "$R" && git init -q . && git config user.email t@t && git config user.name t
printf 'STACK=generic\nTELEMETRY=1\nUSAGE_LOG=1\n' > .sdkit/sdkit.env; echo x > f; git add -A; git commit -qm i; export CLAUDE_PROJECT_DIR="$R"
E() { "$TL" emit "$@" --task t1 >/dev/null 2>&1; }
E task.start --risk high
E phase.enter --from intake --to proposed
E agent.start --span s1 --role developer --host claude --tier standard
E agent.end --span s1 --role developer --host claude --model m1 --tier standard --in 100 --out 50 --dur-ms 4000 --q tokens=actual --outcome ok
"$US" log --role developer --model m1 --provider "" --in 100 --out 50 --id s1 --kind final --slug t1 >/dev/null 2>&1
E failure --category verdict-malformed --reason malformed --role verifier --note "SECRET-NOTE-TEXT /home/me/src/app.go"
E phase.reject --reason verdict-block --from green --to verified
E verify.result --outcome block --role verifier
mkdir -p .sdkit/work/t1; printf '{"type":"decision","ts":"2026-01-01T00:00:01Z","id":"rd-1","role":"verifier","action":"execute","adapter":"claude","model":"m1","tier":"standard","attempt":1,"reason":"ROLE_CAPABILITY_MATCH"}\n' > .sdkit/work/t1/routing.jsonl
out="$("$TL" trace t1 2>&1)"
eq "phases, roles and spans appear"          "$(printf '%s' "$out" | grep -c 'role=developer span=s1')" 2
eq "the usage-ledger request row is joined"  "$(printf '%s' "$out" | grep -c 'ledger(actual)=100/50')" 1
eq "the routing decision is joined"          "$(printf '%s' "$out" | grep -c 'decision=rd-1')" 1
eq "a gate rejection shows its reason code"  "$(printf '%s' "$out" | grep -c 'phase.reject.*reason=verdict-block')" 1
eq "explain names the last problem"          "$(printf '%s' "$out" | grep -c '^explain: last problem = verify.result')" 1
eq "no note text is shown"                   "$(printf '%s' "$out" | grep -c 'SECRET-NOTE-TEXT')" 0
eq "no file path is shown"                   "$(printf '%s' "$out" | grep -c '/home/me')" 0
eq "--json rows carry no note either"        "$("$TL" trace t1 --json | grep -c 'SECRET-NOTE')" 0
eq "--json is valid and chronological"       "$("$TL" trace t1 --json | jq 'map(.ts) == (map(.ts) | sort)')" true
echo "trace: $pass passed, $failed failed"; [ "$failed" = 0 ]
