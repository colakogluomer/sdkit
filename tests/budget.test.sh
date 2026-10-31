#!/usr/bin/env bash
# Token side: hook wiring, usage budget and cache rate, spawn limit, the Agent-tool guard, result-size warning, lookup cache, run-role budget.
# Run: tests/budget.test.sh
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi; }
nocheck() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$n"; else ok "$n"; fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }

echo "hook wiring"
# a JSON object with a repeated key keeps only the last one, which silently drops hooks; the file must not repeat an event
dups="$(grep -oE '^    "[A-Za-z]+": \[' "$KIT/hooks/hooks.json" | sort | uniq -d)"
check "hooks.json repeats no event key"            test -z "$dups"
dups2="$(grep -oE '^    "[A-Za-z]+": \[' "$KIT/templates/settings.copy.json" | sort | uniq -d)"
check "settings.copy.json repeats no event key"    test -z "$dups2"
for h in record-verdict usage-log result-size; do check "SubagentStop runs $h" jq -e --arg h "$h" '.hooks.SubagentStop[].hooks[].command | select(contains($h + ".sh"))' "$KIT/hooks/hooks.json"; done
check "the Agent tool is guarded for budget"        jq -e '.hooks.PreToolUse[] | select(.matcher|test("Agent")) | .hooks[].command | select(contains("guard-budget.sh"))' "$KIT/hooks/hooks.json"
for f in "$KIT"/hooks/guard-budget.sh "$KIT"/hooks/result-size.sh; do check "$(basename "$f") is executable" test -x "$f"; done

repo="$T/repo"; mkdir -p "$repo/.claude/work/t1"; cd "$repo" && git init -q -b main . && git config user.email t@t && git config user.name t
printf 'BASE_BRANCH=main\nUSAGE_LOG=1\n' > .claude/project.env; printf 'work/\n' > .claude/.gitignore; echo a > a.txt; git add -A; git commit -qm i
S="$KIT/scripts/state.sh"; U="$KIT/scripts/usage.sh"
"$S" t1 init medium main >/dev/null
setenv() { printf '%s\n' "$@" > .claude/project.env; printf 'BASE_BRANCH=main\nUSAGE_LOG=1\n' | cat - .claude/project.env > "$T/pe" && mv "$T/pe" .claude/project.env; }

echo "usage: cache rate and budget"
"$U" log --role developer --tier standard --in 1000 --out 500 --cache-read 6000 --cache-write 500 --slug t1 >/dev/null
check "report shows the cache hit rate"            bash -c "'$U' report t1 | grep -q 'cache hit rate: 80%'"
check "no budget set: silent exit 0"               test "$(rc "$U" budget t1)" = 0
check "no budget set: prints nothing"              test -z "$("$U" budget t1)"
setenv TOKEN_BUDGET_TASK=10000
check "under the warn line: exit 0"                test "$(rc "$U" budget t1)" = 0
"$U" log --role developer --in 3000 --out 3000 --slug t1 >/dev/null     # 2000 + 6000 = 8000 of 10000
check "at 80%: exit 3 (warn)"                       test "$(rc "$U" budget t1)" = 3
check "budget line shows used and limit"           bash -c "'$U' budget t1 | grep -q '8000 of 10000 used (80%)'"
setenv TOKEN_BUDGET_TASK=10000 TOKEN_BUDGET_WARN_PCT=90
check "TOKEN_BUDGET_WARN_PCT moves the line"        test "$(rc "$U" budget t1)" = 0
"$U" log --role developer --in 2000 --slug t1 >/dev/null
check "at 100%: exit 4 (over)"                      test "$(rc "$U" budget t1)" = 4
setenv TOKEN_BUDGET_TASK=abc
check "a bad limit is ignored"                      test "$(rc "$U" budget t1)" = 0

echo "spawn counter"
setenv MAX_SPAWNS=2
check "first spawn counted"                         bash -c "'$S' t1 spawn | grep -q 'spawns: 1 of 2'"
check "second spawn allowed"                        "$S" t1 spawn
nocheck "third spawn is over the limit"             "$S" t1 spawn
check "count is kept in state.json"                 test "$("$S" t1 get spawns)" = 3
setenv MAX_SPAWNS=
check "no limit: always allowed"                    "$S" t1 spawn

echo "Agent-tool guard"
G="$KIT/hooks/guard-budget.sh"; call() { printf '{"tool_name":"Agent","tool_input":{}}' | CLAUDE_PROJECT_DIR="$repo" "$G"; }
"$S" t2 init low main >/dev/null; rm -rf .claude/work/t1                       # t2 is now the active task
setenv
check "nothing configured: silent"                  test -z "$(call)"
setenv MAX_SPAWNS=1
check "within the limit: silent"                    test -z "$(call)"
check "strict: over the limit asks"                 bash -c "cd '$repo'; printf '{}' | CLAUDE_PROJECT_DIR='$repo' '$G' | grep -q '\"permissionDecision\": \"ask\"'"
setenv MAX_SPAWNS=1 SDD_MODE=guided
"$S" t2 set spawns 0 >/dev/null 2>&1; jq '.spawns=1' .claude/work/t2/state.json > "$T/s" && mv "$T/s" .claude/work/t2/state.json
check "guided: warns, never asks"                   bash -c "out=\$(printf '{}' | CLAUDE_PROJECT_DIR='$repo' '$G'); echo \"\$out\" | grep -q systemMessage && ! echo \"\$out\" | grep -q permissionDecision"
setenv MAX_SPAWNS=1 SDD_MODE=off
check "off: silent"                                 test -z "$(call)"
setenv MAX_SPAWNS=1
rm -rf .claude/work; check "no active task: silent"  test -z "$(call)"

echo "result-size warning"
R="$KIT/hooks/result-size.sh"; msg() { jq -nc --arg m "$1" '{hook_event_name:"SubagentStop",agent_type:"spec-driven-kit:reviewer",last_assistant_message:$m}' | CLAUDE_PROJECT_DIR="$repo" "$R"; }
long="$(seq 1 50)"
setenv
check "off by default"                              test -z "$(msg "$long")"
setenv SUBAGENT_RESULT_MAX_LINES=20
out="$(msg "$long")"; check "long answer names the role and size" bash -c "echo '$out' | jq -e '.systemMessage | test(\"reviewer returned 50 lines\")'"
check "short answer is silent"                      test -z "$(msg "$(seq 1 5)")"

echo "lookup cache"
L="$KIT/scripts/lookup-cache.sh"
nocheck "miss on an empty cache"                    "$L" get t3 "where is Foo defined?"
check "put stores an answer"                        bash -c "echo 'a.txt:1' | '$L' put t3 'where is Foo defined?'"
check "hit returns the answer"                      bash -c "'$L' get t3 'where is Foo defined?' | grep -q 'a.txt:1'"
check "reworded whitespace and case still hit"      bash -c "'$L' get t3 '  WHERE is   foo defined?'  | grep -q 'a.txt:1'"
nocheck "another question misses"                   "$L" get t3 "who calls Foo?"
echo more >> a.txt
nocheck "an uncommitted edit invalidates"           "$L" get t3 "where is Foo defined?"
git checkout -q a.txt; echo 'b.txt:2' | "$L" put t3 'q2'
git commit -q --allow-empty -m next
nocheck "a new commit invalidates"                  "$L" get t3 'q2'
echo x | "$L" put t3 q3; "$L" clear t3
nocheck "clear forgets everything"                  "$L" get t3 q3

echo "run-role budget"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "{\\"result\\":\\"done\\",\\"usage\\":{}}"\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
printf 'ROLE: scout\nTASK: x\n' > "$T/h.md"
"$S" t4 init low main >/dev/null
RR() { PATH="$T/bin:$PATH" "$KIT/scripts/run-role.sh" scout --handoff "$T/h.md" --host claude "$@"; }
setenv
check "no limits: runs"                             RR
setenv MAX_SPAWNS=1
check "first spawn within the limit"                RR
check "strict: over the limit exits 3"              test "$(rc RR)" = 3
check "--ignore-budget runs anyway"                 RR --ignore-budget
setenv MAX_SPAWNS=1 SDD_MODE=guided
check "guided: runs with a warning"                 RR
setenv MAX_SPAWNS=1 SDD_MODE=off
check "off: runs"                                   RR

echo "budget tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
