#!/usr/bin/env bash
# Benchmark driver: runs a representative SDKit workflow in a throwaway git repo and records what it cost (scripts/telemetry.sh).
#   bench/run.sh list
#   bench/run.sh run <scenario|all> [--out DIR] [--json]                     SIMULATED (default): the real phase machine, gates, run-role.sh
#                                                                           and verdict parsing, but the host CLI is a fixture (bench/stub-host).
#                                                                           Deterministic, free, safe to run anywhere; every number it reports
#                                                                           is a fixture and carries mode "simulated". This is what the tests run.
#   bench/run.sh run <scenario|all> --real --host H [--verifier-host H2] --yes   REAL: the roles are live host CLIs and cost real tokens.
#                                                                           Never started by tests or CI; needs --real and --yes (or a typed yes).
#   bench/run.sh compare A.json B.json                                      side by side of two results (same scenario): tokens, agents, time
#   bench/run.sh list contracts | run contracts [--out DIR]                 the five F02 contract fixtures (GROUP=contract in scenario.env): valid single
#                                                                           handoff, invalid/incomplete handoff, multi-agent chain, interrupted agent, verifier
#                                                                           with independent evidence. `run all` stays the four F01 scenarios, unchanged.
#   bench/run.sh run <scenario|all> --contracts                             the F01 scenario again with contracted handoffs (a fixture agent that follows the
#                                                                           contract), result <scenario>.<mode>.contracts.json: the A/B for the contract overhead
#   bench/run.sh run <scenario> --profile P                                 the scenario with `sdd.sh start --profile P` (result <scenario>.<mode>[.contracts].P.json)
#   bench/run.sh workflow [--out DIR]                                       F03: each F01 scenario as standard and as high-assurance+contracts: script launches
#                                                                           (counted per script), events, and whether it still reaches done
#   bench/run.sh overhead [--out DIR]                                       F01 scenarios with and without contracts: payload bytes, extra script calls, events,
#                                                                           and the validation latency (measured, so it varies) next to parse-verdict.sh
# Scenarios (bench/scenarios/<name>/): scenario.env (RISK, TEST_CMD, STEPS), task.md, proposal.md, base/ (the repo), and for simulated mode
# sim/<step>/ (files the step writes), answers/<step>.txt, usage/<step> ("in out cache_read cache_write"; absent = host prints no usage).
# STEPS = space separated groups; a group is label:role items joined by "," (they run in parallel) and ends with @phase, the phase the
# group runs before: "dev:developer@green verify:verifier@verified". A verifier step that BLOCKs uses the one allowed retry
# (state.sh retry): a "fix" developer step (label fix), then the verifier again (label <verifier>-2).
# Result: <out>/<scenario>.<simulated|real>.json = {scenario, mode, host, deterministic, timing, summary}. "deterministic" is identical across
# simulated runs of the same scenario (counts, tokens, phase order, verdicts); "timing" is not.
# Exit: 0 workflow reached done; 1 it did not (blocked, gate refused); 2 usage.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$KIT/bench"
TELE="$KIT/scripts/telemetry.sh"
command -v jq >/dev/null || { echo "bench needs jq" >&2; exit 1; }

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
group_of() { sed -n 's/^GROUP=//p' "$BENCH/scenarios/$1/scenario.env" | tr -d '"'; }
scenarios() { local s; for s in $(ls "$BENCH/scenarios"); do [ "$(group_of "$s")" = contract ] || echo "$s"; done; }   # the F01 set
contract_scenarios() { local s; for s in $(ls "$BENCH/scenarios"); do [ "$(group_of "$s")" = contract ] && echo "$s"; done; }

# digest <summary json> <scenario> -> the part of a summary that must not change between simulated runs
digest() {
  jq -c --arg s "$2" '{scenario:$s, mode, status, verified, risk, phase_seq:[.phases[].phase],
    agents:{spawned:.agents.spawned, finished:.agents.finished, by_role:[.agents.by_role[] | del(.dur_s)]},
    tokens, cost, retries, failures, tests, verification, events}
    + (if .contracts.checked > 0 then {contracts:(.contracts)} else {} end)' <<< "$1"
}

# run_role <label> <role> <handoff> : one separate-process role through scripts/run-role.sh (host and verifier host come from the repo's settings)
# Exit: run-role's. With contracts: 4 the answer broke the contract, 5 it is valid but not done.
run_role() {
  SDKIT_BENCH_STEP="$1" "$KIT/scripts/run-role.sh" "$2" --handoff "$3" --cwd "$REPO" --out "$REPO/.sdkit/work/$SLUG/out/$1.md" \
    >/dev/null 2>"$REPO/.sdkit/work/$SLUG/out/$1.err"
}

# handoff <label> <role> [retry-of] -> path: the task, the artifacts, and the files earlier steps wrote (the handoff between agents)
# With CONTRACT=1 it is the real contracted brief (references/handoff.md): CONTRACT/ID lines, READ and SCOPE as validated paths.
make_handoff() {
  local label="$1" role="$2" retry="${3:-}" h f
  h="$REPO/.sdkit/work/$SLUG/out/$label.handoff.md"   # (a separate statement: in one `local` line $label would still be the caller's)
  if [ "$CONTRACT" = 1 ]; then contract_handoff "$label" "$role" "$retry" "$h"; echo "$h"; return; fi
  {
    echo "Task $SLUG (risk $RISK): $DESCRIPTION"; echo; cat "$SC/task.md"; echo
    echo "Definition of Done: openspec/changes/$SLUG/proposal.md"
    [ -f "$REPO/openspec/changes/$SLUG/design.md" ] && echo "Design: openspec/changes/$SLUG/design.md"
    echo "Your role: $role. Step: $label."
    case "$role" in verifier*) echo "Verify the diff against the Definition of Done. Do not edit files. Answer in the DOD / FINDINGS / VERIFY / VERDICT format." ;; esac
    local prev=""; for f in "$REPO/.sdkit/work/$SLUG/out/"*.md; do
      case "$f" in *.handoff.md) continue ;; esac
      [ -f "$f" ] && prev="$prev"$'\n'"- ${f#"$REPO/"}"
    done
    [ -n "$prev" ] && printf 'Earlier steps wrote:%s\n' "$prev"
  } > "$h"
  echo "$h"
}

contract_handoff() {  # contract_handoff <label> <role> <retry-of> <file>
  local label="$1" role="$2" retry="$3" h="$4" f reads writes first=1 w
  reads="openspec/changes/$SLUG/proposal.md"; [ -f "$REPO/openspec/changes/$SLUG/design.md" ] && reads="$reads,openspec/changes/$SLUG/design.md"
  case "$role" in
    verifier*|reviewer*|security-auditor*|scout*) writes=none ;;
    *) writes=""
       if [ -d "$SC/sim/$label" ]; then writes="$(cd "$SC/sim/$label" && find . -type f | sed 's#^\./##' | sort | paste -sd, -)"; fi
       [ -n "$writes" ] || writes=".sdkit/work/$SLUG/out/" ;;
  esac
  case "$role" in verifier*) ;; *)   # an independent role gets the artifacts, never what the other agents wrote or thought (handoff.md)
    for f in "$REPO/.sdkit/work/$SLUG/out/"*.md; do
      case "$f" in *.handoff.md) continue ;; esac
      [ -f "$f" ] && reads="$reads,${f#"$REPO/"}"
    done ;;
  esac
  {
    printf 'ROLE: %s     RISK: %s     PROJECT-DIR: .sdkit\nCONTRACT: 1\n' "$role" "$RISK"
    case "$role" in verifier*) printf 'DIFF-BASE: main\n' ;; esac
    printf 'TASK: %s (%s)\nREAD: %s\nSCOPE: writes: %s\nOUT: work/%s/out/%s.md\nID: %s/%s\n' "$DESCRIPTION" "$label" "$reads" "$writes" "$SLUG" "$label" "$SLUG" "$label"
    [ -z "$retry" ] || printf 'RETRY-OF: %s\n' "$retry"
    printf 'REPLY-END: one line "HANDOFF-RESULT/1 | id: <ID> | role: <ROLE> | status: done|partial|blocked|failed | artifacts: <paths|none> | blockers: <text|none> | next: <text|->"\n'
  } > "$h"
  # a scenario can break one handoff on purpose (BAD_HANDOFF="label"): the SCOPE line is dropped from its first attempt
  case " ${BAD_HANDOFF:-} " in *" $label "*) [ -z "$retry" ] && [ ! -e "$REPO/.sdkit/work/$SLUG/out/$label.fixed" ] && sed -i.bak '/^SCOPE:/d' "$h" && rm -f "$h.bak" ;; esac
}

fail_run() {  # fail_run <message>: the workflow did not reach done
  echo "bench: $SLUG: $1" >&2
  "$TELE" emit bench.mark --task "$SLUG" --outcome blocked --note "$1" >/dev/null 2>&1
  "$KIT/scripts/sdd.sh" abort >/dev/null 2>&1
  FAILED=1
}

adv() { "$KIT/scripts/sdd.sh" advance "$@" >"$REPO/.sdkit/work/$SLUG/out/advance.log" 2>&1 || { fail_run "advance $1 refused: $(tail -1 "$REPO/.sdkit/work/$SLUG/out/advance.log")"; return 1; }; }

# contracted_role <label> <role> [handoff]: what the orchestrator does with a contract. A handoff the contract refuses before the spawn is corrected
# and sent again (nothing was spent); an agent that crashed or whose answer broke the contract gets the one allowed retry under a new id (RETRY-OF);
# an agent that reports blocked/failed is not retried blindly (exit 5 stops the workflow for the user).
contracted_role() {
  local label="$1" role="$2" h rc
  h="${3:-$(make_handoff "$label" "$role")}"
  run_role "$label" "$role" "$h"; rc=$?
  if [ "$rc" = 2 ]; then   # refused before the spawn
    : > "$REPO/.sdkit/work/$SLUG/out/$label.fixed"
    run_role "$label" "$role" "$(make_handoff "$label" "$role")"; rc=$?
  fi
  case "$rc" in
    0) return 0 ;;
    5) return 5 ;;
    2) return 2 ;;
    *) "$KIT/scripts/state.sh" "$SLUG" retry "$label" >/dev/null 2>&1 || return "$rc"
       run_role "$label-2" "$role" "$(make_handoff "$label-2" "$role" "$SLUG/$label")" ;;
  esac
}

# verify_step <label> <role>: run the verifier, record its verdict, use the one retry on BLOCK
# The verdict comes from parse-verdict.sh alone. A contract problem on the verifier's answer (exit 4/5) is already in the telemetry and does not
# decide anything here.
verify_step() {
  local label="$1" role="$2" attempt rc a="$1" out rrc
  for attempt in 1 2; do
    run_role "$a" "$role" "$(make_handoff "$a" "$role")"; rrc=$?
    case "$rrc" in 0|4|5) [ "$CONTRACT" = 1 ] || [ "$rrc" = 0 ] || { fail_run "$role exited $rrc"; return 1; } ;; *) fail_run "$role exited non-zero"; return 1 ;; esac
    out="$REPO/.sdkit/work/$SLUG/out/$a.md"
    (cd "$REPO" && "$KIT/scripts/parse-verdict.sh" "$out" --proposal "openspec/changes/$SLUG/proposal.md") >"$REPO/.sdkit/work/$SLUG/out/$a.verdict" 2>&1; rc=$?   # check only: run-role.sh already recorded it, with the run it registered (F04)
    [ "$rc" = 0 ] && return 0
    if [ "$rc" = 2 ]; then   # a verdict that cannot be recorded: ask once more (what the orchestrator does), count it
      "$TELE" emit verify.result --task "$SLUG" --outcome malformed --source verifier >/dev/null 2>&1
      "$TELE" emit failure --task "$SLUG" --category verdict-malformed --source verifier >/dev/null 2>&1
    fi
    [ "$attempt" = 1 ] || { fail_run "verifier did not PASS after the retry"; return 1; }
    if [ "$rc" = 1 ]; then
      "$KIT/scripts/state.sh" "$SLUG" retry "$label" >/dev/null 2>&1 || { fail_run "retry already used"; return 1; }
      run_role fix developer "$(make_handoff fix developer)" || { [ "$CONTRACT" = 1 ] || { fail_run "developer exited non-zero"; return 1; }; }
    fi
    a="$label-2"
  done
}

# run_group <group spec> : label:role[,label:role...]  (members of a group run in parallel)
run_group() {
  local item label role pids="" p ok=0 h
  for item in ${1//,/ }; do   # every handoff of a group is written before any member starts, so none depends on a sibling's timing
    label="${item%%:*}"; role="${item#*:}"
    case "$role" in verifier*) ;; *) make_handoff "$label" "$role" >/dev/null ;; esac
  done
  for item in ${1//,/ }; do
    label="${item%%:*}"; role="${item#*:}"
    case "$role" in
      verifier*) verify_step "$label" "$role" || return 1 ;;   # the verifier is always alone in its group
      *) h="$REPO/.sdkit/work/$SLUG/out/$label.handoff.md"
         if [ "$CONTRACT" = 1 ]; then ( contracted_role "$label" "$role" "$h" ) & pids="$pids $!"
         else ( run_role "$label" "$role" "$h" ) & pids="$pids $!"; fi ;;
    esac
  done
  for p in $pids; do wait "$p" || ok=1; done
  [ "$ok" = 0 ] || { fail_run "a role exited non-zero"; return 1; }
}

run_scenario() {  # run_scenario <name> -> writes the result file; returns 0 when the workflow reached done
  SLUG="$1"; SC="$BENCH/scenarios/$SLUG"; FAILED=0
  [ -d "$SC" ] || { echo "no scenario '$SLUG' (bench/run.sh list)" >&2; return 2; }
  DESCRIPTION=""; RISK=low; TEST_CMD=""; STEPS=""; VERIFIER_HOST=""; CONTRACT=0; BAD_HANDOFF=""; GROUP=""
  # scenario.env is trusted kit content, written for this driver: plain KEY="value" lines
  . "$SC/scenario.env"
  [ "$CONTRACTS_FLAG" = 1 ] && [ "$GROUP" != contract ] && CONTRACT=1   # the F01 scenario, contracted (A/B)
  local suffix=""; [ "$CONTRACTS_FLAG" = 1 ] && suffix=".contracts"; [ -n "$PROFILE_FLAG" ] && suffix="$suffix.$PROFILE_FLAG"
  REPO="$(mktemp -d)"; [ "$KEEP" = 1 ] && echo "bench: $SLUG repo kept at $REPO" >&2
  cp -R "$SC/base/." "$REPO/"
  mkdir -p "$REPO/.sdkit" "$REPO/openspec/changes/$SLUG"
  local mode=simulated host="${HOST:-claude}" vhost="${VERIFIER_HOST:-}"
  [ "$REAL" = 1 ] && { mode=real; vhost="${VERIFIER_HOST_REAL:-}"; }
  {
    printf 'BASE_BRANCH=main\nSTACK=generic\nSDD_MODE=strict\nVERIFY_TEST_CMD=%s\n' "\"$TEST_CMD\""
    [ "$CONTRACT" = 1 ] && printf 'CONTRACTS=1\n'
  } > "$REPO/.sdkit/sdkit.env"
  {
    printf 'TELEMETRY=1\nUSAGE_LOG=1\nRUN_ROLE_HOST=%s\n' "$host"
    [ -n "$vhost" ] && printf 'VERIFIER_HOST=%s\n' "$vhost"
  } > "$REPO/.sdkit/sdkit.local.env"
  printf 'work/\n.sdd/\n.verify-cache/\nsdkit.local.env\n' > "$REPO/.sdkit/.gitignore"
  ( cd "$REPO" && git init -q -b main . && git config user.email bench@example.org && git config user.name bench \
      && git add -A && git commit -qm base && git checkout -qb feat ) || { echo "bench: git setup failed" >&2; return 1; }
  cp "$SC/proposal.md" "$REPO/openspec/changes/$SLUG/proposal.md"
  [ -f "$SC/design.md" ] && cp "$SC/design.md" "$REPO/openspec/changes/$SLUG/design.md"
  mkdir -p "$REPO/.sdkit/work/$SLUG/out"

  export CLAUDE_PROJECT_DIR="$REPO" VERIFY_BASE=main SDKIT_TELEMETRY_MODE="$mode"
  unset SDKIT_RUN_ID
  if [ "$REAL" = 0 ]; then export SDKIT_BENCH_SCENARIO="$SC" PATH="$BENCH/stub-host:$PATH"; fi
  [ "$CONTRACTS_FLAG" = 1 ] && [ "$GROUP" != contract ] && export SDKIT_BENCH_CONTRACT=auto
  local t0 t1; t0="$("$TELE" now-ms)"
  cd "$REPO" || return 1
  "$KIT/scripts/state.sh" "$SLUG" init "$RISK" feat >/dev/null
  "$KIT/scripts/sdd.sh" start "$SLUG" --risk "$RISK" ${PROFILE_FLAG:+--profile "$PROFILE_FLAG"} --proposal "openspec/changes/$SLUG/proposal.md" >/dev/null || fail_run "start refused"
  local group phase spec target
  for target in proposed red green verified pr done; do
    [ "$FAILED" = 0 ] || break
    for group in $STEPS; do
      spec="${group%@*}"; phase="${group##*@}"
      [ "$phase" = "$target" ] && { run_group "$spec" || break; }
    done
    [ "$FAILED" = 0 ] || break
    case "$target" in
      red|green) adv "$target" --test-cmd "$TEST_CMD" ;;
      *) adv "$target" ;;
    esac || break
  done
  t1="$("$TELE" now-ms)"
  cd "$KIT" || true
  local sum; sum="$(CLAUDE_PROJECT_DIR="$REPO" "$TELE" summary "$SLUG" --json)"
  echo "$sum" | jq -e '.task' >/dev/null 2>&1 || { echo "bench: no telemetry for $SLUG" >&2; rm -rf "$REPO"; return 1; }
  mkdir -p "$OUT"
  local nh hb ab; nh="$(ls "$REPO/.sdkit/work/$SLUG/out/"*.handoff.md 2>/dev/null | wc -l | tr -d ' ')"
  hb="$(cat "$REPO/.sdkit/work/$SLUG/out/"*.handoff.md 2>/dev/null | wc -c | tr -d ' ')"
  ab="$(ls "$REPO/.sdkit/work/$SLUG/out/"*.md 2>/dev/null | grep -v '\.handoff\.md$' | while read -r f; do cat "$f"; done | wc -c | tr -d ' ')"
  jq -n --arg s "$SLUG" --arg m "$mode" --arg h "$host" --arg v "$vhost" --argjson d "$(digest "$sum" "$SLUG")" --argjson sum "$sum" --argjson ms "$((t1 - t0))" \
    --argjson nh "$nh" --argjson hb "$hb" --argjson ab "$ab" --arg c "$CONTRACT" \
    '{scenario:$s, mode:$m, host:$h, verifier_host:(if $v == "" then null else $v end), contracts:($c == "1"), payload:{handoffs:$nh, handoff_bytes:$hb, answer_bytes:$ab}, deterministic:$d, timing:{wall_ms:$ms, note:"varies between runs"}, summary:$sum}' \
    > "$OUT/$SLUG.$mode$suffix.json"
  [ "$KEEP" = 1 ] || rm -rf "$REPO"
  if [ "$JSON" = 1 ]; then cat "$OUT/$SLUG.$mode$suffix.json"
  else jq -r '"\(.scenario) [\(.mode)\(if .contracts then "+contracts" else "" end)] \(.summary.status) agents=\(.summary.agents.finished) tokens in/out=\(.summary.tokens.in)/\(.summary.tokens.out) measured=\(.summary.tokens.runs_measured)/\(.summary.tokens.runs_measured + .summary.tokens.runs_unmeasured) retries=\(.summary.retries) failures=\(.summary.failures.total) wall=\(.timing.wall_ms)ms"' "$OUT/$SLUG.$mode$suffix.json"; fi
  return "$FAILED"
}

ms_now() { perl -MTime::HiRes=time -e 'printf "%.0f", time*1000' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }
contract_lines_bytes() {
  { printf 'CONTRACT: 1\nID: some-task/dev-a\n'; printf 'REPLY-END: one line "HANDOFF-RESULT/1 | id: <ID> | role: <ROLE> | status: done|partial|blocked|failed | artifacts: <paths|none> | blockers: <text|none> | next: <text|->"\n'; } | wc -c | tr -d ' '
}
latency() {  # latency <n>: wall time per call of the validators, in a scratch repo
  local n="$1" r t0 t1 i
  r="$(mktemp -d)"; mkdir -p "$r/.sdkit" "$r/src"; ( cd "$r" && git init -q -b main . && printf 'BASE_BRANCH=main\nSTACK=generic\n' > .sdkit/sdkit.env && echo p > plan.md && echo a > src/a.sh )
  export CLAUDE_PROJECT_DIR="$r"; ( cd "$r" && "$KIT/scripts/state.sh" lat init low main >/dev/null 2>&1 )
  printf 'ROLE: developer\nCONTRACT: 1\nTASK: t\nREAD: plan.md\nSCOPE: writes: src/\nID: lat/dev\n' > "$r/h.md"
  printf 'done\nHANDOFF-RESULT/1 | id: lat/dev | role: developer | status: done | artifacts: src/a.sh | blockers: none | next: -\n' > "$r/a.txt"
  printf 'DOD\n- D1 a | PASS | t\nFINDINGS\n- none\nVERIFY\n- command: t | result: green | ok\nVERDICT: PASS\n' > "$r/v.txt"
  ( cd "$r" && "$KIT/scripts/contract.sh" issue h.md >/dev/null
    for c in "contract.sh issue h.md --check-only" "contract.sh check-result a.txt --role developer" "parse-verdict.sh v.txt"; do
      t0="$(ms_now)"; i=0; while [ "$i" -lt "$n" ]; do "$KIT/scripts/${c%% *}" ${c#* } >/dev/null 2>&1; i=$((i + 1)); done; t1="$(ms_now)"
      printf '  %-44s %s ms per call\n' "$c" "$(awk -v a="$((t1 - t0))" -v n="$n" 'BEGIN{printf "%.1f", a / n}')"
    done )
  rm -rf "$r"
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  list) if [ "${1:-}" = contracts ]; then for s in $(contract_scenarios); do printf '%-30s %s\n' "$s" "$(sed -n 's/^DESCRIPTION="\(.*\)"/\1/p' "$BENCH/scenarios/$s/scenario.env")"; done; exit 0; fi
        for s in $(scenarios); do printf '%-26s %s\n' "$s" "$(sed -n 's/^DESCRIPTION="\(.*\)"/\1/p' "$BENCH/scenarios/$s/scenario.env")"; done ;;
  run)
    which="${1:-}"; [ -n "$which" ] && shift || usage
    REAL=0; HOST=""; VERIFIER_HOST_REAL=""; YES=0; OUT="${TMPDIR:-/tmp}/sdkit-bench-$$"; JSON=0; KEEP=0; CONTRACTS_FLAG=0; PROFILE_FLAG=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --real) REAL=1 ;; --host) HOST="$2"; shift ;; --verifier-host) VERIFIER_HOST_REAL="$2"; shift ;; --yes) YES=1 ;;
        --out) OUT="$2"; shift ;; --json) JSON=1 ;; --keep) KEEP=1 ;; --contracts) CONTRACTS_FLAG=1 ;; --profile) PROFILE_FLAG="$2"; shift ;; *) echo "unknown option $1" >&2; usage ;;
      esac; shift
    done
    if [ "$REAL" = 1 ] && [ "$CONTRACTS_FLAG" = 1 ]; then echo "bench: --contracts is simulated only (a real contracted run needs the user's decision: docs/design-contracts.md §10)" >&2; exit 2; fi
    if [ "$REAL" = 1 ]; then
      [ -n "$HOST" ] || { echo "bench: --real needs --host (claude|codex|opencode|cursor|gemini)" >&2; exit 2; }
      if [ "$YES" != 1 ]; then
        [ -t 0 ] || { echo "bench: a real run spends real tokens: pass --yes to confirm" >&2; exit 2; }
        printf 'This runs live %s agents and spends real tokens. Type yes to continue: ' "$HOST" >&2; read -r ans; [ "$ans" = yes ] || exit 2
      fi
    elif [ -n "$HOST$VERIFIER_HOST_REAL" ]; then echo "bench: --host is for --real runs; simulated runs use the fixtures" >&2; exit 2; fi
    rc=0
    if [ "$which" = all ]; then for s in $(scenarios); do ( run_scenario "$s" ) || rc=1; done
    elif [ "$which" = contracts ]; then [ "$CONTRACTS_FLAG" = 0 ] || { echo "bench: the contract fixtures are contracted already" >&2; exit 2; }
      for s in $(contract_scenarios); do ( run_scenario "$s" ) || rc=1; done
    else ( run_scenario "$which" ) || rc=$?; fi
    exit "$rc" ;;
  overhead)
    OUT="${TMPDIR:-/tmp}/sdkit-bench-overhead-$$"; N=100
    while [ $# -gt 0 ]; do case "$1" in --out) OUT="$2"; shift ;; --n) N="$2"; shift ;; *) usage ;; esac; shift; done
    mkdir -p "$OUT"; for s in $(scenarios); do "$0" run "$s" --out "$OUT" >/dev/null 2>&1; "$0" run "$s" --contracts --out "$OUT" >/dev/null 2>&1; done
    echo "Contract overhead, simulated fixtures (deterministic columns; no tokens or cost are claimed)"
    printf '%-26s %6s %12s %12s %10s %10s %8s %8s\n' scenario agents "handoff B" "(contract)" "answer B" "(contract)" "events" "(contr.)"
    for s in $(scenarios); do
      a="$OUT/$s.simulated.json"; b="$OUT/$s.simulated.contracts.json"; [ -f "$a" ] && [ -f "$b" ] || { echo "$s: missing result" >&2; continue; }
      jq -rn --slurpfile a "$a" --slurpfile b "$b" '($a[0]) as $x | ($b[0]) as $y
        | "\($x.scenario | (. + "                          ")[0:26]) \($x.summary.agents.finished | tostring | ("      " + .)[-6:]) \($x.payload.handoff_bytes | tostring | ("            " + .)[-12:]) \($y.payload.handoff_bytes | tostring | ("            " + .)[-12:]) \($x.payload.answer_bytes | tostring | ("          " + .)[-10:]) \($y.payload.answer_bytes | tostring | ("          " + .)[-10:]) \($x.summary.events | tostring | ("        " + .)[-8:]) \($y.summary.events | tostring | ("        " + .)[-8:])"'
    done
    echo; echo "Per contracted agent (counted from the events): contract.sh calls = contract.check events; telemetry.sh emits = contract.check + failure/contract"
    for s in $(scenarios); do jq -r '"  \(.scenario): \(.summary.contracts.checked) contract.sh calls, \(.summary.contracts.checked + .summary.contracts.invalid) telemetry emits, \(.summary.agents.finished) agents; invalid \(.summary.contracts.invalid)"' "$OUT/$s.simulated.contracts.json"; done
    echo "  (tokens are fixture values in simulated mode: a token or cost difference cannot be read from this table)"
    echo; echo "Fixed text a contract adds per exchange (bytes of the lines the handoff and the answer carry):"
    h="$(contract_lines_bytes)"; echo "  handoff: $h bytes (CONTRACT, ID, REPLY-END)   result line: $(printf '%s' 'HANDOFF-RESULT/1 | id: <task>/<label> | role: developer | status: done | artifacts: src/a.sh | blockers: none | next: -' | wc -c | tr -d ' ') bytes (typical)"
    echo "Validation latency, measured on this machine over $N runs each (varies; not part of any deterministic result):"
    latency "$N" ;;
  workflow)
    OUT="${TMPDIR:-/tmp}/sdkit-bench-workflow-$$"
    while [ $# -gt 0 ]; do case "$1" in --out) OUT="$2"; shift ;; *) usage ;; esac; shift; done
    mkdir -p "$OUT"
    # variant <scenario> <name> <run args...>: run with the script-launch counter on; prints "name status events launches workflow.sh contract.sh telemetry.sh sdd.sh"
    variant() {
      local s="$1" name="$2" calls rc st ev; shift 2; calls="$OUT/$s.$name.calls"; : > "$calls"
      SDKIT_CALLS="$calls" BASH_ENV="$BENCH/call-counter.sh" "$0" run "$s" --out "$OUT" "$@" >/dev/null 2>"$OUT/$s.$name.err"; rc=$?
      st=done; [ "$rc" = 0 ] || st="refused"
      ev="$(jq -r '.summary.events // "-"' "$OUT/$s.simulated$([ "$name" = standard ] || echo ".contracts.high-assurance").json" 2>/dev/null || echo -)"
      printf '%-26s %-15s %-8s %6s %8s %6s %6s %6s %6s\n' "$s" "$name" "$st" "$ev" "$(wc -l < "$calls" | tr -d ' ')" \
        "$(grep -c '^workflow.sh' "$calls")" "$(grep -c '^contract.sh' "$calls")" "$(grep -c '^telemetry.sh' "$calls")" "$(grep -c '^sdd.sh' "$calls")"
    }
    echo "Workflow overhead, simulated fixtures (script launches counted with BASH_ENV; no tokens or cost are claimed)"
    printf '%-26s %-15s %-8s %6s %8s %6s %6s %6s %6s\n' scenario variant result events launches wf.sh ctr.sh tele.sh sdd.sh
    for s in $(scenarios); do
      variant "$s" standard
      variant "$s" high-assurance --contracts --profile high-assurance
    done ;;
  compare)
    [ -f "${1:-}" ] && [ -f "${2:-}" ] || usage
    jq -rn --slurpfile a "$1" --slurpfile b "$2" '
      ($a[0]) as $x | ($b[0]) as $y
      | if $x.scenario != $y.scenario then "different scenarios: \($x.scenario) vs \($y.scenario)" else
        "scenario \($x.scenario)   A: \($x.mode)   B: \($y.mode)",
        (["status", "agents", "tokens in", "tokens out", "cache_read", "retries", "failures", "tokens measured", "wall ms"] as $names
         | [[$x.summary.status, $y.summary.status],
            [$x.summary.agents.finished, $y.summary.agents.finished],
            [$x.summary.tokens.in, $y.summary.tokens.in], [$x.summary.tokens.out, $y.summary.tokens.out], [$x.summary.tokens.cache_read, $y.summary.tokens.cache_read],
            [$x.summary.retries, $y.summary.retries], [$x.summary.failures.total, $y.summary.failures.total],
            ["\($x.summary.tokens.runs_measured)/\($x.summary.tokens.runs_measured + $x.summary.tokens.runs_unmeasured)", "\($y.summary.tokens.runs_measured)/\($y.summary.tokens.runs_measured + $y.summary.tokens.runs_unmeasured)"],
            [$x.timing.wall_ms, $y.timing.wall_ms]] as $v
         | range(0; $names | length) | "  \($names[.] + "                  " | .[0:18])\($v[.][0] | tostring | (. + "              ")[0:14])\($v[.][1])"),
        (if $x.mode != $y.mode then "  note: simulated and real results are not comparable" else empty end),
        (if ($x.summary.tokens.complete | not) or ($y.summary.tokens.complete | not) then "  note: a side has runs without token data; its totals are lower bounds" else empty end)
        end' ;;
  *) usage ;;
esac
