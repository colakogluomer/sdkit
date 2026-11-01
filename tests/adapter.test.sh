#!/usr/bin/env bash
# F12 execution-adapter contract: built-ins unchanged, a mock external adapter through run-role.sh, honest unsupported capabilities. No model, no network.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; AD="$ROOT/scripts/adapter.sh"; RR="$ROOT/scripts/run-role.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }
R="$T/r"; mkdir -p "$R/.sdkit/adapters.d"; cd "$R" && git init -q . && git config user.email t@t && git config user.name t
printf 'STACK=generic\nUSAGE_LOG=1\n' > .sdkit/sdkit.env; echo x > f; git add -A; git commit -qm i
export CLAUDE_PROJECT_DIR="$R"
cat > .sdkit/adapters.d/mock.sh <<'X'
#!/usr/bin/env bash
case "$1" in
  capabilities) echo '{"noninteractive":"declared","tool_use":"none","model_selection":"none","usage_reporting":"declared","structured_output":"declared","cancellation":"none","timeout":"kit","cost_reporting":"none"}' ;;
  execute) echo '{"result":"mock answer","usage":{"input_tokens":11,"output_tokens":7}}' ;;
  status) echo "idle" ;;
  *) exit 3 ;;
esac
X
cat > .sdkit/adapters.d/quiet.sh <<'X'
#!/usr/bin/env bash
case "$1" in capabilities) echo '{"noninteractive":"declared","tool_use":"none","model_selection":"none","usage_reporting":"none","structured_output":"none","cancellation":"none","timeout":"kit","cost_reporting":"none"}' ;; execute) echo '{"result":"quiet answer"}' ;; *) exit 3 ;; esac
X
cat > .sdkit/adapters.d/bad.sh <<'X'
#!/usr/bin/env bash
[ "$1" = capabilities ] && echo '{"noninteractive":"verified"}'
X
chmod +x .sdkit/adapters.d/*.sh
printf 'TASK: look\n' > h.md

echo "contract verbs"
eq "built-in capabilities have 8 keys"        "$("$AD" capabilities claude --json | jq 'keys | length')" 8
eq "mock capabilities validate"               "$("$AD" validate ext:mock 2>&1 | cut -c1-6)" valid:
eq "a bad adapter is invalid (exit 1)"        "$("$AD" validate ext:bad >/dev/null 2>&1; echo $?)" 1
eq "a missing adapter is exit 2"              "$("$AD" validate ext:nope >/dev/null 2>&1; echo $?)" 2
eq "an unsafe adapter name is refused"        "$("$AD" validate 'ext:../x' >/dev/null 2>&1; echo $?)" 2
eq "cancel on a built-in is unsupported (3)"  "$("$AD" cancel codex >/dev/null 2>&1; echo $?)" 3
eq "cancel on mock is unsupported (3)"        "$("$AD" cancel ext:mock >/dev/null 2>&1; echo $?)" 3
eq "status on mock is supported"              "$("$AD" status ext:mock 2>&1)" idle
eq "usage: codex reports none, not zero"      "$("$AD" usage codex | cut -c1-5)" none:
eq "usage: mock reports declared"             "$("$AD" usage ext:mock | cut -c1-9)" declared:

echo "execution through run-role.sh (gates and usage path unchanged)"
out="$("$RR" scout --handoff h.md --host ext:mock --cwd "$R" 2>/dev/null)"; rc=$?
eq "run-role runs the mock adapter"           "$rc:$(printf '%s' "$out" | head -1)" "0:mock answer"
L="$(find .sdkit -name usage.jsonl | head -1)"
eq "usage was recorded as measured tokens"    "$(jq -rs '[.[] | select(.host == "ext:mock") | .in] | first' "$L" 2>/dev/null)" 11
"$RR" scout --handoff h.md --host ext:quiet --cwd "$R" >/dev/null 2>&1
eq "an adapter without usage is unmeasured, not zero" "$(jq -rs '[.[] | select(.host == "ext:quiet")] | first | .tq' "$L" 2>/dev/null)" unavailable
eq "an unknown adapter is refused (exit 2)"   "$("$RR" scout --handoff h.md --host ext:nope --cwd "$R" >/dev/null 2>&1; echo $?)" 2
eq "an unknown plain host is refused (exit 2)" "$("$RR" scout --handoff h.md --host zzz --cwd "$R" >/dev/null 2>&1; echo $?)" 2
eq "the claude command line is unchanged"     "$("$RR" scout --handoff h.md --host claude --cwd "$R" --dry-run 2>&1 | grep -c 'claude -p <prompt:[0-9]* chars> --output-format json')" 1

echo "adapter: $pass passed, $failed failed"; [ "$failed" = 0 ]
