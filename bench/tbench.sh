#!/usr/bin/env bash
# Task-level benchmark (F05-A): the same software task, solved by different strategies, scored by an evaluator the agent cannot reach.
# bench/run.sh measures what SDKit's own workflow costs on scenarios; this measures whether the work is CORRECT and what it cost, against a baseline.
#   tbench.sh tasks                                         the registered tasks (id, version, difficulty, risk)
#   tbench.sh strategies                                    the strategies and their configuration; validates them
#   tbench.sh validate [ID|all]                             manifest schema, checksums, registry entry, starter tree, requirement coverage, no hidden-path leaks
#   tbench.sh seal ID|all                                   maintainer: recompute checksums into task.json and registry.json (a sealed id@version never changes: bump version)
#   tbench.sh fixtures [ID|all]                             prove each task: starter fails hidden tests, partial fails, reference passes, test tampering does not help
#   tbench.sh run (--simulate | --real --yes) --out DIR [--task ID,..|all] [--strategy S,..|all] [--reps N] [--run-id ID | --run-id-prefix P]
#                 [--model M] [--provider P] [--billing metered|subscription|unknown] [--prices FILE] [--agent-timeout S] [--keep-workspace]
#                 [--sim-force VARIANT] [--sim-metrics none|invalid]
#       --simulate  no model is invoked: a deterministic fixture agent (bench/lib/sim-agent.sh) acts for the strategy. Results are labeled simulated.
#       --real      needs an isolation mechanism that passes `preflight`, else it fails closed (exit 3). F05-A ships no real agent adapter: it stops after the gate.
#   tbench.sh preflight [--isolation-cmd "CMD ARGS"]        probe that CMD (or $SDKIT_TBENCH_ISOLATION_CMD) really hides the evaluator assets
#   tbench.sh ingest FILE [--telemetry] [--prices F] [--billing B]   normalize a metrics file (agent-metrics/1, or a telemetry.sh summary --json)
#   tbench.sh verify DIR                                    check every sealed result in DIR/runs (exit 6 when one changed after writing)
#   tbench.sh report --results DIR [--min-n N] [--json] [--stdout-only]   aggregate sealed results into Markdown (or JSON) and write DIR/reports/
# Exit: 0 ok; 1 failure; 2 usage; 3 refused (fail closed); 4 run id already exists; 5 task integrity (checksum mismatch); 6 sealed result changed; 130 interrupted.
# Layout: tasks/<id>-<slug>/{task.json,task.md,starter/}  evaluator/<id>-<slug>/{hidden/,variants/{reference,partial}/}  strategies/*.json  sim/  lib/
# Results: DIR/runs/<run-id>/{result.json,result.sha256,agent.log,public.log,hidden.log,diagnostics/}; DIR/work/ holds throw-away workspaces only.
# Security boundary (docs/design-benchmark.md): a git worktree or temp directory is NOT a sandbox against arbitrary shell access of the same user.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$KIT/bench"
LIB="$BENCH/lib"
TASKS="${SDKIT_TBENCH_TASKS:-$BENCH/tasks}"
EVALS="${SDKIT_TBENCH_EVALUATOR:-$BENCH/evaluator}"
STRATS="${SDKIT_TBENCH_STRATEGIES:-$BENCH/strategies}"
SIMF="${SDKIT_TBENCH_SIM:-$BENCH/sim/sim.json}"
command -v jq >/dev/null || { echo "tbench needs jq" >&2; exit 1; }
command -v python3 >/dev/null || { echo "tbench needs python3 (fixtures and the process runner)" >&2; exit 1; }

die() { echo "tbench: $1" >&2; exit "${2:-1}"; }
usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
g() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"; }   # no user config, no global excludes: the starter tree hash must not depend on the machine
sha_file() { if command -v shasum >/dev/null; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
sha_stdin() { if command -v shasum >/dev/null; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# dirsum <base> <path>...: one hash over the sorted (hash, path) list of the regular files below the paths
dirsum() {
  local base="$1"; shift
  ( cd "$base" 2>/dev/null || exit 1
    find "$@" -type f ! -name .DS_Store ! -name '*.pyc' ! -path '*__pycache__*' 2>/dev/null | LC_ALL=C sort \
      | while IFS= read -r f; do printf '%s  %s\n' "$(sha_file "$f")" "$f"; done ) | sha_stdin
}
tree_of() {  # <dir>: the git tree id of a directory's content (identical content, identical id, on any machine)
  local t; t="$(mktemp -d)"
  cp -R "$1/." "$t/" && find "$t" \( -name .DS_Store -o -name __pycache__ \) -prune -exec rm -rf {} + 2>/dev/null
  ( cd "$t" && g init -q . && g add -A && g write-tree ) 2>/dev/null
  rm -rf "$t"
}
task_dirs() { local f; for f in "$TASKS"/*/task.json; do [ -f "$f" ] && dirname "$f"; done; }
task_id() { jq -r '.id // empty' "$1/task.json" 2>/dev/null; }
task_dir_of() { local d; for d in $(task_dirs); do [ "$(task_id "$d")" = "$1" ] && { echo "$d"; return 0; }; done; return 1; }
eval_dir_of() { echo "$EVALS/$(basename "$(jq -r '.hidden_test.evaluator_dir' "$1/task.json")")"; }
resolve_tasks() {  # <ID,ID|all> -> task dirs
  local s="$1" id d
  if [ "$s" = all ]; then task_dirs; return; fi
  for id in $(echo "$s" | tr ',' ' '); do d="$(task_dir_of "$id")" || die "unknown task $id" 2; echo "$d"; done
}
strategy_names() { local f; for f in "$STRATS"/*.json; do [ -f "$f" ] && basename "$f" .json; done; }

# ---------- validation ----------
manifest_errors() {  # <task.json>
  jq -r '
    def hex: type == "string" and test("^[0-9a-f]{64}$");
    def safe: type == "string" and length > 0 and (startswith("/") | not) and (contains("..") | not);
    def pint: type == "number" and . >= 1 and . == floor;
    def lvl: . == "low" or . == "medium" or . == "high";
    [ (if .schema != "tbench-task/1" then "schema must be tbench-task/1" else empty end),
      (if ((.id // "") | type) != "string" or ((.id // "") | test("^T[0-9]{2}$") | not) then "id must look like T01" else empty end),
      (if (.version | pint | not) then "version must be a positive integer" else empty end),
      (if ((.title // "") | type) != "string" or (.title // "") == "" then "title is required" else empty end),
      (if ((.description // "") | type) != "string" or (.description // "") == "" then "description is required" else empty end),
      (if (.difficulty | lvl | not) then "difficulty must be low|medium|high" else empty end),
      (if (.risk | lvl | not) then "risk must be low|medium|high" else empty end),
      (if ((.starter.repo // "") | safe | not) then "starter.repo missing" else empty end),
      (if ((.starter.tree // "") | test("^[0-9a-f]{40}$") | not) then "starter.tree (git tree id) missing: run seal" else empty end),
      (if ((.starter.provenance // "") == "") then "starter.provenance is required" else empty end),
      (if ((.public_test // "") == "") then "public_test command is required" else empty end),
      (if ((.hidden_test.command // "") == "") then "hidden_test.command is required" else empty end),
      (if ((.hidden_test.min_tests | pint) | not) then "hidden_test.min_tests must be a positive integer" else empty end),
      (if ((.hidden_test.evaluator_dir // "") | safe | not) then "hidden_test.evaluator_dir missing" else empty end),
      (if ((.editable // []) | length) == 0 or ((.editable // []) | map(safe) | all | not) then "editable must list safe relative paths" else empty end),
      (if ((.requirements // []) | length) == 0 then "requirements are required"
       elif ((.requirements | map(.id) | unique | length) != (.requirements | length)) or ((.requirements | map(.id | test("^R[0-9]+$")) | all) | not) then "requirement ids must be unique R<n>" else empty end),
      (if ([.limits.agent_timeout_s, .limits.test_timeout_s, .limits.max_output_bytes] | map(pint) | all | not) then "limits need agent_timeout_s, test_timeout_s, max_output_bytes" else empty end),
      (if (.environment | type) != "object" then "environment is required" else empty end),
      (if ((.checksums.visible_sha256 // "") | hex | not) or ((.checksums.evaluator_sha256 // "") | hex | not) then "checksums missing: run seal" else empty end)
    ] | .[]' "$1" 2>&1
}
cmd_validate_dir() {  # <taskdir> -> prints problems; returns 0 ok, 1 invalid, 5 checksum/tree mismatch
  local d="$1" errs="" rc=0 id ver e m want got ev sum reg r
  [ -f "$d/task.json" ] || { echo "  - no task.json"; return 1; }
  jq -e . "$d/task.json" >/dev/null 2>&1 || { echo "  - task.json is not valid JSON"; return 1; }
  errs="$(manifest_errors "$d/task.json")"
  [ -f "$d/task.md" ] && [ -d "$d/starter" ] || errs="$errs"$'\n'"task.md and starter/ are required"
  ev="$(eval_dir_of "$d")"
  [ -d "$ev/hidden" ] && [ -d "$ev/variants/reference" ] || errs="$errs"$'\n'"evaluator assets missing ($ev/hidden, variants/reference)"
  if [ -n "$errs" ] && [ "$(printf '%s' "$errs" | tr -d '[:space:]')" != "" ]; then printf '%s\n' "$errs" | sed '/^$/d; s/^/  - /'; return 1; fi
  if grep -rIlE 'hidden_tests|evaluator|variants/(reference|partial)' "$d/task.md" "$d/starter" >/dev/null 2>&1; then
    echo "  - agent-visible files (task.md, starter/) mention hidden/evaluator paths"; rc=1; fi
  if find "$d/starter" -type l | grep -q .; then echo "  - starter contains symlinks"; rc=1; fi
  for r in $(jq -r '.requirements[].id' "$d/task.json"); do
    grep -rq "test_${r}_" "$ev/hidden" 2>/dev/null || { echo "  - requirement $r has no hidden test named test_${r}_*"; rc=1; }
  done
  want="$(jq -r '.checksums.visible_sha256' "$d/task.json")"; got="$(dirsum "$d" task.md starter)"
  [ "$want" = "$got" ] || { echo "  - visible content checksum mismatch (task.md/starter changed after sealing)"; rc=5; }
  want="$(jq -r '.checksums.evaluator_sha256' "$d/task.json")"; got="$(dirsum "$ev" hidden variants)"
  [ "$want" = "$got" ] || { echo "  - evaluator content checksum mismatch (hidden/variants changed after sealing)"; rc=5; }
  want="$(jq -r '.starter.tree' "$d/task.json")"; got="$(tree_of "$d/starter")"
  [ "$want" = "$got" ] || { echo "  - starter tree mismatch (manifest $want, content $got)"; rc=5; }
  id="$(jq -r '.id' "$d/task.json")"; ver="$(jq -r '.version' "$d/task.json")"
  reg="$TASKS/registry.json"
  if [ -f "$reg" ]; then
    m="$(jq -r --arg k "$id@$ver" '.tasks[$k].manifest_sha256 // empty' "$reg")"
    if [ -z "$m" ]; then echo "  - $id@$ver is not in registry.json (run seal)"; rc=1
    elif [ "$m" != "$(sha_file "$d/task.json")" ]; then echo "  - task.json changed since $id@$ver was sealed: bump the version"; rc=5; fi
  else echo "  - registry.json missing"; rc=1; fi
  return $rc
}
cmd_validate() {
  local sel="${1:-all}" d bad=0 out rc worst=0
  for d in $(resolve_tasks "$sel"); do
    out="$(cmd_validate_dir "$d")"; rc=$?
    if [ $rc = 0 ]; then echo "OK    $(jq -r '.id + "@" + (.version | tostring)' "$d/task.json")  $(basename "$d")"
    else echo "FAIL  $(basename "$d")"; printf '%s\n' "$out"; bad=1; [ $rc -gt $worst ] && worst=$rc; fi
  done
  [ $bad = 0 ] || exit "$worst"
}
cmd_seal() {
  local sel="${1:-}" d id ver ev reg="$TASKS/registry.json" tmp key old new
  [ -n "$sel" ] || usage
  [ -f "$reg" ] || echo '{"schema":"tbench-registry/1","tasks":{}}' > "$reg"
  for d in $(resolve_tasks "$sel"); do
    ev="$(eval_dir_of "$d")"; [ -d "$ev/hidden" ] || die "$(basename "$d"): no evaluator assets in $ev" 1
    tmp="$(mktemp)"
    jq --arg tree "$(tree_of "$d/starter")" --arg v "$(dirsum "$d" task.md starter)" --arg e "$(dirsum "$ev" hidden variants)" \
      '.starter.tree = $tree | .checksums.visible_sha256 = $v | .checksums.evaluator_sha256 = $e' "$d/task.json" > "$tmp" || die "cannot seal $d" 1
    id="$(jq -r .id "$tmp")"; ver="$(jq -r .version "$tmp")"; key="$id@$ver"; new="$(sha_file "$tmp")"
    old="$(jq -r --arg k "$key" '.tasks[$k].manifest_sha256 // empty' "$reg")"
    if [ -n "$old" ] && [ "$old" != "$new" ]; then rm -f "$tmp"; die "$key is already sealed with different content: bump \"version\" in task.json" 5; fi
    cp "$tmp" "$d/task.json"; rm -f "$tmp"
    jq --arg k "$key" --arg dir "$(basename "$d")" --arg h "$new" '.tasks[$k] = {dir: $dir, manifest_sha256: $h}' "$reg" > "$reg.new" && mv "$reg.new" "$reg"
    echo "sealed $key"
  done
}

# ---------- limited process runner ----------
RUN_PID=""; INTERRUPTED=0
on_interrupt() { INTERRUPTED=1; [ -n "$RUN_PID" ] && kill -TERM "$RUN_PID" 2>/dev/null; return 0; }
# run_limited <cwd> <home> <timeout> <max-bytes> <log> <meta-file> <env-assignments-file|-> -- <argv...>: a scrubbed environment (only what is passed), group kill, size cap
run_limited() {
  local cwd="$1" home="$2" to="$3" mx="$4" log="$5" meta="$6" envf="$7"; shift 8
  local -a extra=()
  if [ "$envf" != "-" ] && [ -f "$envf" ]; then while IFS= read -r l; do [ -n "$l" ] && extra+=("$l"); done < "$envf"; fi
  mkdir -p "$home"
  env -i PATH="$PATH" HOME="$home" LANG=C TZ=UTC PYTHONDONTWRITEBYTECODE=1 PYTHONHASHSEED=0 ${extra[@]+"${extra[@]}"} \
    python3 "$LIB/runlimited.py" --timeout "$to" --max-bytes "$mx" --out "$log" --cwd "$cwd" -- "$@" > "$meta" 2>/dev/null &
  RUN_PID=$!
  wait "$RUN_PID"; wait "$RUN_PID" 2>/dev/null
  RUN_PID=""
  jq -e . "$meta" >/dev/null 2>&1 || echo '{"exit":-1,"timed_out":false,"truncated":false,"interrupted":false,"dur_s":0}' > "$meta"
}

# ---------- evaluation (outside the agent's environment) ----------
# evaluate <taskdir> <candidate-workspace> <outdir>: builds a fresh tree = pristine starter + ONLY the candidate's editable paths, adds the hidden tests, runs both suites.
# Tests the candidate wrote or changed are ignored by construction. Writes <outdir>/evaluation.json, public.log, hidden.log.
evaluate() {
  local td="$1" ws="$2" out="$3" ev tree p err="" pm hm pout hout pexit hexit ran min reqs lines
  ev="$(eval_dir_of "$td")"; tree="$out/tree"; mkdir -p "$out/home"
  rm -rf "$tree"; mkdir -p "$tree"; cp -R "$td/starter/." "$tree/"
  for p in $(jq -r '.editable[]' "$td/task.json"); do
    rm -rf "${tree:?}/$p"
    [ -e "$ws/$p" ] || [ -L "$ws/$p" ] || continue
    if [ -n "$(find "$ws/$p" -type l 2>/dev/null | head -1)" ]; then err="candidate $p contains a symlink"; break; fi
    mkdir -p "$tree/$(dirname "$p")"; cp -R "$ws/$p" "$tree/$p"
  done
  find "$tree" \( -name __pycache__ -o -name .DS_Store \) -prune -exec rm -rf {} + 2>/dev/null
  if [ -n "$err" ]; then
    jq -n --arg e "$err" '{public:{outcome:"not-run"}, hidden:{outcome:"not-run", requirements:{}}, error:$e}' > "$out/evaluation.json"; return 0
  fi
  local tt mb; tt="$(jq -r '.limits.test_timeout_s' "$td/task.json")"; mb="$(jq -r '.limits.max_output_bytes' "$td/task.json")"
  pm="$out/public.meta"; hm="$out/hidden.meta"
  run_limited "$tree" "$out/home" "$tt" "$mb" "$out/public.log" "$pm" - -- bash -c "$(jq -r '.public_test' "$td/task.json")"
  mkdir -p "$tree/hidden_tests"; cp -R "$ev/hidden/." "$tree/hidden_tests/"
  run_limited "$tree" "$out/home" "$tt" "$mb" "$out/hidden.log" "$hm" - -- bash -c "$(jq -r '.hidden_test.command' "$td/task.json")"
  rm -rf "$tree/hidden_tests"
  pexit="$(jq -r .exit "$pm")"; hexit="$(jq -r .exit "$hm")"
  pout=fail; [ "$pexit" = 0 ] && pout=pass; [ "$(jq -r .timed_out "$pm")" = true ] && pout=timeout; [ "$(jq -r .truncated "$pm")" = true ] && pout=error
  ran="$(sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' "$out/hidden.log" | tail -1)"; ran="${ran:-0}"
  min="$(jq -r '.hidden_test.min_tests' "$td/task.json")"
  lines="$(grep -E '^test_R[0-9]+_.* \.\.\. ' "$out/hidden.log" 2>/dev/null | sed -E 's/^test_(R[0-9]+)_.* \.\.\. ([A-Za-z]+).*$/\1 \2/')"
  reqs="$(printf '%s\n' "$lines" | jq -Rn --argjson ids "$(jq -c '[.requirements[].id]' "$td/task.json")" \
    '[inputs | select(length > 0) | split(" ") | {r: .[0], s: .[1]}] as $t
     | $ids | map(. as $id | ($t | map(select(.r == $id))) as $m
         | {key: $id, value: (if ($m | length) == 0 then "untested" elif ($m | all(.s == "ok")) then "pass" else "fail" end)}) | from_entries')"
  hout=fail
  if [ "$hexit" = 0 ] && [ "$ran" -ge "$min" ] && ! grep -q 'skipped=' "$out/hidden.log" && [ "$(jq -c '[.[] | select(. != "pass")] | length' <<< "$reqs")" = 0 ]; then hout=pass
  elif [ "$hexit" = 0 ] && [ "$ran" -lt "$min" ]; then hout=error; fi
  [ "$(jq -r .timed_out "$hm")" = true ] && hout=timeout; [ "$(jq -r .truncated "$hm")" = true ] && hout=error
  jq -n --arg po "$pout" --argjson pe "$pexit" --arg ho "$hout" --argjson he "$hexit" --argjson ran "$ran" --argjson min "$min" --argjson reqs "$reqs" \
    --slurpfile pm "$pm" --slurpfile hm "$hm" \
    '{public: {outcome: $po, exit: $pe, timed_out: $pm[0].timed_out, dur_s: $pm[0].dur_s},
      hidden: {outcome: $ho, exit: $he, timed_out: $hm[0].timed_out, dur_s: $hm[0].dur_s, tests_run: $ran, min_tests: $min, requirements: $reqs},
      error: null}' > "$out/evaluation.json"
}

# ---------- fixtures ----------
cmd_fixtures() {
  local sel="${1:-all}" d id ev t ws v bad=0 line pub hid nreq
  for d in $(resolve_tasks "$sel"); do
    id="$(task_id "$d")"; ev="$(eval_dir_of "$d")"; t="$(mktemp -d)"
    for v in starter partial reference tamper; do
      ws="$t/ws-$v"; mkdir -p "$ws"; cp -R "$d/starter/." "$ws/"
      case "$v" in
        partial|reference) [ -d "$ev/variants/$v" ] || { echo "FAIL  $id: no variant $v"; bad=1; continue; }; cp -R "$ev/variants/$v/." "$ws/" ;;
        tamper) printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ok(self):\n        pass\n' > "$ws/tests/test_public.py"
                mkdir -p "$ws/hidden_tests"; printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_R1_x(self):\n        pass\n' > "$ws/hidden_tests/test_hidden.py" ;;
      esac
      evaluate "$d" "$ws" "$t/out-$v"
      pub="$(jq -r .public.outcome "$t/out-$v/evaluation.json")"; hid="$(jq -r .hidden.outcome "$t/out-$v/evaluation.json")"
      nreq="$(jq -r '[.hidden.requirements[] | select(. != "pass")] | length' "$t/out-$v/evaluation.json")"
      case "$v:$pub:$hid" in
        starter:pass:fail|partial:pass:fail|tamper:pass:fail) line="ok    $id $v: public=$pub hidden=$hid (requirements not met: $nreq)" ;;
        reference:pass:pass) line="ok    $id $v: public=$pub hidden=$hid" ;;
        *) line="FAIL  $id $v: public=$pub hidden=$hid"; bad=1 ;;
      esac
      echo "$line"
    done
    rm -rf "$t"
  done
  [ $bad = 0 ] || exit 1
}

# ---------- strategies ----------
strategy_errors() {  # <file>
  jq -r --arg n "$(basename "$1" .json)" '
    [ (if .schema != "tbench-strategy/1" then "schema must be tbench-strategy/1" else empty end),
      (if .name != $n then "name must equal the file name" else empty end),
      (if (.workflow != "none" and .workflow != "sdkit") then "workflow must be none|sdkit" else empty end),
      (if .workflow == "none" and (.sdkit != false or .profile != null) then "a baseline must not use SDKit or a profile" else empty end),
      (if .workflow == "sdkit" and (.sdkit != true or (.profile != "standard" and .profile != "high-assurance")) then "an SDKit strategy needs sdkit=true and profile standard|high-assurance" else empty end),
      (if .workflow == "sdkit" and .risk_floor != "inherit" then "SDKit strategies must inherit the risk floor (risk_floor=inherit)" else empty end),
      (if (.env | type) != "object" then "env must be an object" else empty end),
      ((.env // {}) | keys[] | select(test("^(SDD_MODE|RISK_FLOOR.*|HOOKS?_.*|SDKIT_.*)$")) | "env may not set " + . + ": it would weaken SDKit enforcement or the harness"),
      (if ((.same_as_other_strategies // []) | index("model")) == null then "same_as_other_strategies must include model" else empty end)
    ] | .[]' "$1" 2>&1
}
cmd_strategies() {
  local s f bad=0 e
  for s in $(strategy_names); do
    f="$STRATS/$s.json"; e="$(strategy_errors "$f")"
    if [ -z "$e" ]; then printf 'OK    %-22s workflow=%s profile=%s independent_verification=%s\n' "$s" "$(jq -r .workflow "$f")" "$(jq -r '.profile // "-"' "$f")" "$(jq -r .independent_verification "$f")"
    else echo "FAIL  $s"; printf '%s\n' "$e" | sed 's/^/  - /'; bad=1; fi
  done
  [ $bad = 0 ]
}

# ---------- isolation gate ----------
cmd_preflight() {
  local cmd="${SDKIT_TBENCH_ISOLATION_CMD:-}" f d probe
  while [ $# -gt 0 ]; do case "$1" in --isolation-cmd) cmd="$2"; shift ;; *) usage ;; esac; shift; done
  [ -n "$cmd" ] || die "no isolation mechanism configured (SDKIT_TBENCH_ISOLATION_CMD or --isolation-cmd): refusing, hidden-test isolation cannot be claimed" 3
  local -a iso; read -r -a iso <<< "$cmd"
  "${iso[@]}" true >/dev/null 2>&1 || die "the isolation command does not run a trivial program: refusing" 3
  f="$(find "$EVALS" -path '*/hidden/*' -type f 2>/dev/null | head -1)"; [ -n "$f" ] || die "no evaluator assets found under $EVALS" 3
  [ -r "$f" ] || die "evaluator asset not readable even outside the isolation: cannot probe" 3
  for probe in "cat $f" "ls $(dirname "$f")" "cat $(find "$EVALS" -path '*/variants/reference/*' -type f 2>/dev/null | head -1)"; do
    # shellcheck disable=SC2086
    if "${iso[@]}" $probe >/dev/null 2>&1; then die "NOT ISOLATED: '$probe' succeeds under '$cmd'. Refusing (fail closed)." 3; fi
  done
  d="$("${iso[@]}" env 2>/dev/null | grep -c "$EVALS")"
  [ "${d:-0}" = 0 ] || die "NOT ISOLATED: the evaluator path appears in the environment under '$cmd'" 3
  echo "isolation probe passed: evaluator hidden tests and references are unreadable under: $cmd"
  echo "(this probes the evaluator assets only; it does not prove the mechanism is a complete sandbox)"
}

# ---------- metrics ----------
cmd_ingest() {
  local f="" tele=0 prices='{}' billing=unknown
  while [ $# -gt 0 ]; do
    case "$1" in --telemetry) tele=1 ;; --prices) prices="$(jq -c . "$2")" || die "bad prices file" 2; shift ;; --billing) billing="$2"; shift ;; *) f="$1" ;; esac; shift
  done
  [ -f "$f" ] || usage
  ingest_file "$f" "$tele" "$prices" "$billing" "" ""
}
ingest_file() {  # <file|""> <telemetry 0|1> <prices json> <billing> <model> <provider>
  local f="$1" tele="$2" prices="$3" billing="$4" model="$5" provider="$6" raw='{}'
  if [ -n "$f" ] && [ -f "$f" ] && jq -e . "$f" >/dev/null 2>&1; then
    if [ "$tele" = 1 ]; then raw="$(jq -c -f "$LIB/from-telemetry.jq" "$f")"; else raw="$(jq -c . "$f")"; fi
  fi
  jq -c --arg b "$billing" --arg m "$model" --arg p "$provider" \
    'if type == "object" and length > 0 then (.billing //= $b | (if $m != "" then .model //= $m else . end) | (if $p != "" then .provider //= $p else . end)) else . end' <<< "$raw" \
    | jq -c --argjson prices "$prices" -f "$LIB/ingest.jq"
}

# ---------- running ----------
safe_rm_work() {  # only ever deletes a directory below <out>/work that carries the workspace marker
  local d="$1" real base
  [ -d "$d" ] && [ -f "$d/.tbench-workspace" ] || return 0
  real="$(cd "$d" && pwd -P)"; base="$(cd "$OUT/work" && pwd -P)"
  case "$real" in "$base"/?*) rm -rf "$real" ;; *) echo "tbench: refusing to delete $real (outside $base)" >&2 ;; esac
}
env_json() {
  jq -n --arg os "$(uname -s)" --arg rel "$(uname -r)" --arg arch "$(uname -m)" --arg bash "${BASH_VERSION:-}" --arg jq "$(jq --version 2>/dev/null)" \
    --arg py "$(python3 -V 2>&1)" --arg git "$(g --version 2>/dev/null)" '{os:$os, os_release:$rel, arch:$arch, bash:$bash, jq:$jq, python:$py, git:$git}'
}
runner_json() {
  local commit dirty=false v
  commit="$(git -C "$KIT" rev-parse HEAD 2>/dev/null || echo unknown)"
  [ -n "$(git -C "$KIT" status --porcelain -- bench scripts 2>/dev/null | head -1)" ] && dirty=true
  v="$(jq -r '.version // "unknown"' "$KIT/.claude-plugin/plugin.json" 2>/dev/null)"
  jq -n --arg c "$commit" --argjson d "$dirty" --arg v "$v" --arg code "$(dirsum "$BENCH" tbench.sh lib)" '{kit_version:$v, commit:$c, dirty:$d, schema:1, code_sha256:$code}'
}
seal_run() {  # <rundir>
  ( cd "$1" && sha_file result.json > result.sha256 )
  chmod -R a-w "$1" 2>/dev/null; return 0
}
sim_entry() {  # <strategy> <task id> -> JSON {variant, metrics, kind}
  jq -c --arg s "$1" --arg t "$2" --arg force "$SIM_FORCE" '
    .strategies[$s] as $p | (.task_scale[$t] // 1) as $k | (.outcomes[$s][$t] // "starter") as $v | (.overrides[$s + "/" + $t] // {}) as $o
    | def n($x): ($x * $k | floor);
      {variant: (if $force != "" then $force else ($o.variant // $v) end), kind: $p.kind, label: .label,
       base: {in: n($p.in), out: n($p.out), cache_read: n($p.cache_read), cache_write: n($p.cache_write), llm_calls: n($p.llm_calls),
              agent_calls: ($p.agent_calls + ((.task_extra_agents[$t] // 0) * ($p.extra_agent_factor // 0))), retries: (($p.retries // 0) + ($o.retries // 0)), usage: ($o.usage // "measured"),
              roles: ($p.roles | to_entries | map({key, value: .value}) | from_entries),
              phases: ($p.phases | map({name: .[0], frac: .[1]})), dur_s: n($p.dur_s)}}' "$SIMF"
}
write_sim_outputs() {  # <entry json> <outdir> <metrics mode>: what a strategy adapter would leave behind for the harness
  local e="$1" od="$2" mode="$3"
  mkdir -p "$od"
  [ "$mode" = none ] && return 0
  if [ "$mode" = invalid ]; then echo '{"tokens":{"in":"many","out":-5},"tokens_quality":"measured","llm_calls":1.5}' > "$od/metrics.json"; return 0; fi
  if [ "$(jq -r .kind <<< "$e")" = telemetry ]; then
    jq '.base as $b | {task: "sim", run: "sim", mode: "simulated", risk: null, status: "done", verified: true, wall_s: $b.dur_s,
         phases: ($b.phases | map({phase: .name, dur_s: (.frac * $b.dur_s | floor)})),
         agents: {spawned: $b.agent_calls, finished: $b.agent_calls,
                  by_role: ($b.roles | to_entries | map({role: .key, runs: 1, in: (.value * $b.in | floor), out: (.value * $b.out | floor), cache_read: (.value * $b.cache_read | floor), cache_write: (.value * $b.cache_write | floor), runs_without_tokens: 0}))},
         tokens: (if $b.usage == "unavailable" then {in: 0, out: 0, cache_read: 0, cache_write: 0, runs_measured: 0, runs_unmeasured: $b.agent_calls, quality: "unavailable", complete: false}
                  else {in: $b.in, out: $b.out, cache_read: $b.cache_read, cache_write: $b.cache_write, runs_measured: $b.agent_calls, runs_unmeasured: 0, quality: "actual", complete: true} end),
         cost: {usd: null, quality: "unavailable"}, retries: $b.retries}' <<< "$e" > "$od/telemetry-summary.json"
  else
    jq '.base as $b | {schema: "agent-metrics/1", source: "simulation",
         tokens: (if $b.usage == "unavailable" then null else {in: $b.in, out: $b.out, cache_read: $b.cache_read, cache_write: $b.cache_write} end),
         tokens_quality: (if $b.usage == "unavailable" then "unavailable" else "measured" end),
         cost: {provider_usd: (if $b.usage == "unavailable" then null else (($b.in * 3 + $b.out * 15 + $b.cache_read * 0.3 + $b.cache_write * 3.75) / 1000000) end)},
         llm_calls: $b.llm_calls, agent_calls: $b.agent_calls, retries: $b.retries,
         quality: {llm_calls: "measured", agent_calls: "measured", retries: "measured"},
         phases: ($b.phases | map({name, dur_s: (.frac * $b.dur_s)})),
         roles: ($b.roles | to_entries | map({key, value: {in: (.value * $b.in | floor), out: (.value * $b.out | floor), cache_read: (.value * $b.cache_read | floor), cache_write: (.value * $b.cache_write | floor), calls: 1}}) | from_entries)}' <<< "$e" > "$od/metrics.json"
  fi
}

# run_one <taskdir> <strategy> <run-id>
run_one() {
  local td="$1" strat="$2" id="$3" tid rundir work ws sf entry variant t0 t1 sim_dir agent_meta ainfo aexit atimeo atrunc aintr dur
  local ev patch files ins del tests_touched category success outcome evaljson metrics diag started msrc kind
  tid="$(task_id "$td")"; sf="$STRATS/$strat.json"
  [ -z "$(strategy_errors "$sf")" ] || die "strategy $strat is invalid (tbench.sh strategies)" 1
  cmd_validate_dir "$td" >/dev/null || die "task $tid failed integrity validation (tbench.sh validate $tid): refusing to run" 5
  mkdir -p "$OUT/runs" "$OUT/work"
  rundir="$OUT/runs/$id"
  mkdir "$rundir" 2>/dev/null || die "run id '$id' already exists in $OUT/runs: results are never overwritten" 4
  printf '%s\n%s\n' "$$" "$(now_iso)" > "$rundir/RUNNING"
  work="$OUT/work/$id"; ws="$work/ws"; mkdir -p "$work/home" "$work/agent-out" && touch "$work/.tbench-workspace"
  started="$(now_iso)"; t0="$(date +%s)"
  # workspace: independent git repo from the pristine starter, fixed identity and dates (deterministic commit content)
  mkdir -p "$ws"; cp -R "$td/starter/." "$ws/"; find "$ws" \( -name .DS_Store -o -name __pycache__ \) -prune -exec rm -rf {} + 2>/dev/null
  ( cd "$ws" && g init -q -b main . && g add -A && GIT_AUTHOR_NAME=tbench GIT_AUTHOR_EMAIL=tbench@localhost GIT_COMMITTER_NAME=tbench GIT_COMMITTER_EMAIL=tbench@localhost \
      GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" g commit -q -m "starter $tid" ) >/dev/null 2>&1 || die "cannot create the workspace" 1
  local scommit stree
  scommit="$(g -C "$ws" rev-parse HEAD)"; stree="$(g -C "$ws" rev-parse 'HEAD^{tree}')"
  [ "$stree" = "$(jq -r .starter.tree "$td/task.json")" ] || die "starter tree mismatch for $tid" 5
  # nothing evaluator-side may be in the agent's workspace
  ev="$(eval_dir_of "$td")"
  if find "$ev" -type f ! -name .DS_Store | while IFS= read -r f; do sha_file "$f"; done | sort -u > "$work/evalhashes" \
     && find "$ws" -path "$ws/.git" -prune -o -type f -print | while IFS= read -r f; do sha_file "$f"; done | sort -u | grep -q -F -f "$work/evalhashes"; then
    die "evaluator content found inside the agent workspace: refusing" 1; fi
  cp "$td/task.md" "$work/prompt.md"
  # the agent: only an explicit allowlist of variables; no path to the evaluator
  entry="$(sim_entry "$strat" "$tid")"; variant="$(jq -r .variant <<< "$entry")"; kind="$(jq -r .kind <<< "$entry")"
  : > "$work/agent.env"
  { echo "SDKIT_TBENCH_RUN_ID=$id"; echo "SDKIT_TBENCH_PROMPT=$work/prompt.md"; echo "SDKIT_TBENCH_OUT=$work/agent-out"; echo "SDKIT_TBENCH_STRATEGY=$strat"
    echo "SDKIT_TBENCH_SIM_VARIANT=$variant"; echo "SDKIT_TBENCH_PAYLOAD=$work/payload"; } >> "$work/agent.env"
  case "$variant" in reference|partial)
    mkdir -p "$work/payload"; [ -d "$ev/variants/$variant" ] && cp -R "$ev/variants/$variant/." "$work/payload/" ;; esac
  write_sim_outputs "$entry" "$work/sim-src" "$SIM_METRICS"
  echo "SDKIT_TBENCH_SIM_SRC=$work/sim-src" >> "$work/agent.env"
  local atimeout mb
  atimeout="${AGENT_TIMEOUT:-$(jq -r .limits.agent_timeout_s "$td/task.json")}"; mb="$(jq -r .limits.max_output_bytes "$td/task.json")"
  run_limited "$ws" "$work/home" "$atimeout" "$mb" "$rundir/agent.log" "$work/agent.meta" "$work/agent.env" -- bash "$LIB/sim-agent.sh"
  aexit="$(jq -r .exit "$work/agent.meta")"; atimeo="$(jq -r .timed_out "$work/agent.meta")"; atrunc="$(jq -r .truncated "$work/agent.meta")"; aintr="$(jq -r .interrupted "$work/agent.meta")"
  [ "$INTERRUPTED" = 1 ] && aintr=true
  dur="$(jq -r .dur_s "$work/agent.meta")"
  # code changes
  ( cd "$ws" && g add -A >/dev/null 2>&1 )
  g -C "$ws" diff --cached HEAD -- . ':!*.pyc' ':!*__pycache__*' > "$work/changes.patch" 2>/dev/null
  read -r files ins del tests_touched < <(g -C "$ws" diff --cached --numstat HEAD -- . ':!*.pyc' ':!*__pycache__*' 2>/dev/null \
    | awk 'BEGIN{f=0;i=0;d=0;t=0} {f++; if ($1 ~ /^[0-9]+$/) i+=$1; if ($2 ~ /^[0-9]+$/) d+=$2; if ($3 ~ /^tests\//) t++} END{print f, i, d, t}')
  files="${files:-0}"; ins="${ins:-0}"; del="${del:-0}"; tests_touched="${tests_touched:-0}"
  if [ "$aintr" = true ]; then
    evaljson='{"public":{"outcome":"not-run"},"hidden":{"outcome":"not-run","requirements":{}},"error":null}'
  else
    evaluate "$td" "$ws" "$work/eval"; evaljson="$(jq -c . "$work/eval/evaluation.json")"
    cp "$work/eval/public.log" "$rundir/public.log" 2>/dev/null; cp "$work/eval/hidden.log" "$rundir/hidden.log" 2>/dev/null
  fi
  # metrics: whatever the strategy left behind, normalized; absent stays unavailable
  if [ -f "$work/agent-out/telemetry-summary.json" ]; then metrics="$(ingest_file "$work/agent-out/telemetry-summary.json" 1 "$PRICES" "$BILLING" "$MODEL" "$PROVIDER")"
  else metrics="$(ingest_file "$work/agent-out/metrics.json" 0 "$PRICES" "$BILLING" "$MODEL" "$PROVIDER")"; fi
  # outcome and failure category
  category=null; success=true; outcome=success
  if [ "$aintr" = true ]; then category='"interrupted"'; outcome=interrupted; success=false
  elif [ "$(jq -r '.error // empty' <<< "$evaljson")" != "" ]; then category='"eval-error"'; outcome=failure; success=false
  elif [ "$atimeo" = true ]; then category='"agent-timeout"'; outcome=failure; success=false
  elif [ "$atrunc" = true ]; then category='"agent-output-limit"'; outcome=failure; success=false
  elif [ "$aexit" != 0 ]; then category='"agent-crash"'; outcome=failure; success=false
  elif [ "$(jq -r .hidden.outcome <<< "$evaljson")" != pass ]; then
    outcome=failure; success=false
    if [ "$(jq -r '.hidden.outcome' <<< "$evaljson")" = error ] || [ "$(jq -r '.hidden.outcome' <<< "$evaljson")" = timeout ]; then category='"eval-error"'
    elif [ "$files" = 0 ]; then category='"no-change"'
    elif [ "$tests_touched" = "$files" ]; then category='"tests-only-change"'
    else category='"hidden-fail"'; fi
  elif [ "$(jq -r .public.outcome <<< "$evaljson")" != pass ]; then category='"public-regression"'; outcome=failure; success=false
  fi
  t1="$(date +%s)"
  local simulated=true label; label="$(jq -r '.label // empty' "$SIMF")"
  jq -n --arg id "$id" --arg started "$started" --arg ended "$(now_iso)" --argjson wall "$((t1 - t0))" --argjson sim "$simulated" --arg label "${label:-SIMULATED}" \
    --slurpfile man "$td/task.json" --slurpfile strat "$sf" --slurpfile base "$STRATS/baseline.json" --arg scommit "$scommit" --arg stree "$stree" \
    --arg mpath "$(sha_file "$td/task.json")" --argjson runner "$(runner_json)" --argjson envj "$(env_json)" --argjson evaljson "$evaljson" --argjson metrics "$metrics" \
    --argjson ameta "$(jq -c . "$work/agent.meta")" --argjson cat "$category" --argjson success "$success" --arg outcome "$outcome" \
    --argjson files "$files" --argjson ins "$ins" --argjson del "$del" --argjson tt "$tests_touched" --arg variant "$variant" --arg ecode "$(dirsum "$BENCH" tbench.sh lib)" \
    '$man[0] as $m | $strat[0] as $s | $base[0] as $b | {
      schema: "tbench-result/1", run_id: $id, mode: "simulated", simulated: $sim,
      label: (if $sim then $label else null end),
      task: {id: $m.id, version: $m.version, title: $m.title, risk: $m.risk, difficulty: $m.difficulty, checksums: $m.checksums, manifest_sha256: $mpath},
      starter: {commit: $scommit, tree: $stree},
      strategy: {name: $s.name, config: $s, differs_from_baseline: ($s | to_entries | map(select(.value != $b[.key])) | map({key: .key, baseline: $b[.key], this: .value}))},
      model: $metrics.model, provider: $metrics.provider, billing: $metrics.billing,
      runner: $runner, evaluator: {code_sha256: $ecode, task_sha256: $m.checksums.evaluator_sha256},
      environment: $envj, isolation: {mechanism: "none", hidden_test_isolation: "not claimed (simulation: the fixture agent is harness code, not an untrusted process)"},
      simulation: (if $sim then {variant: $variant} else null end),
      started: $started, ended: $ended, duration_s: $wall,
      agent: {exit: $ameta.exit, timed_out: $ameta.timed_out, output_truncated: $ameta.truncated, interrupted: $ameta.interrupted, duration_s: $ameta.dur_s},
      evaluation: $evaljson, changes: {files: $files, insertions: $ins, deletions: $del, test_files_touched: $tt},
      metrics: $metrics, outcome: $outcome, success: $success, failure_category: $cat
    }' > "$rundir/result.json" || die "could not write the result" 1
  # diagnostics: kept for every run that did not succeed (or with --keep-workspace)
  if [ "$success" != true ] || [ "$KEEP" = 1 ]; then
    diag="$rundir/diagnostics"; mkdir -p "$diag"; mv "$ws" "$diag/workspace" 2>/dev/null; cp "$work/changes.patch" "$diag/" 2>/dev/null
    cp "$work/agent.meta" "$diag/" 2>/dev/null; [ -d "$work/eval" ] && cp "$work/eval/evaluation.json" "$diag/" 2>/dev/null
  fi
  rm -f "$rundir/RUNNING"
  safe_rm_work "$work"
  seal_run "$rundir"
  printf '%-9s %s  %s/%s  hidden=%s public=%s%s\n' "$outcome" "$id" "$tid" "$strat" "$(jq -r .hidden.outcome <<< "$evaljson")" "$(jq -r .public.outcome <<< "$evaljson")" \
    "$([ "$category" != null ] && echo "  [$(jq -r . <<< "$category")]")"
  [ "$aintr" = true ] && return 130
  return 0
}

cmd_run() {
  local mode="" tsel=all ssel=all reps=1 rid="" prefix="" yes=0 n=0 t s r id d rc
  OUT=""; MODEL=""; PROVIDER=""; BILLING=""; PRICES='{}'; AGENT_TIMEOUT=""; KEEP=0; SIM_FORCE=""; SIM_METRICS=ok
  while [ $# -gt 0 ]; do
    case "$1" in
      --simulate) mode=simulate ;; --real) mode=real ;; --yes) yes=1 ;;
      --out) OUT="$2"; shift ;; --task) tsel="$2"; shift ;; --strategy) ssel="$2"; shift ;; --reps) reps="$2"; shift ;;
      --run-id) rid="$2"; shift ;; --run-id-prefix) prefix="$2"; shift ;;
      --model) MODEL="$2"; shift ;; --provider) PROVIDER="$2"; shift ;; --billing) BILLING="$2"; shift ;;
      --prices) PRICES="$(jq -c . "$2")" || die "bad prices file" 2; shift ;;
      --agent-timeout) AGENT_TIMEOUT="$2"; shift ;; --keep-workspace) KEEP=1 ;;
      --sim-force) SIM_FORCE="$2"; shift ;; --sim-metrics) SIM_METRICS="$2"; shift ;;
      *) usage ;;
    esac; shift
  done
  [ -n "$mode" ] && [ -n "$OUT" ] || usage
  case "$reps" in ''|*[!0-9]*|0) die "--reps must be a positive integer" 2 ;; esac
  case "$BILLING" in ''|metered|subscription|unknown) ;; *) die "--billing must be metered|subscription|unknown" 2 ;; esac
  case "$SIM_METRICS" in ok|none|invalid) ;; *) die "--sim-metrics must be ok|none|invalid" 2 ;; esac
  case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
  case "$OUT" in "$KIT"|"$KIT"/*) die "--out must be outside the kit checkout ($KIT): benchmark results never go into the source tree" 2 ;; esac
  mkdir -p "$OUT" || die "cannot create $OUT" 1
  OUT="$(cd "$OUT" && pwd -P)"
  case "$OUT" in "$KIT"|"$KIT"/*) die "--out resolves into the kit checkout: refusing" 2 ;; esac
  if [ "$mode" = real ]; then
    [ "$yes" = 1 ] || die "--real spends money: pass --yes to confirm" 3
    cmd_preflight || exit 3
    die "real agent adapters are not part of F05-A (see docs/design-benchmark.md, prerequisites for F05-B). Nothing was run." 3
  fi
  [ -f "$SIMF" ] || die "no simulation data at $SIMF" 1
  MODEL="${MODEL:-sim-model}"; PROVIDER="${PROVIDER:-simulation}"; BILLING="${BILLING:-metered}"
  [ "$PRICES" != '{}' ] || PRICES="$(jq -c '.prices // {}' "$SIMF")"
  [ -z "$rid" ] || { [ "$tsel" != all ] && [ "$ssel" != all ] && [ "$reps" = 1 ] && ! echo "$tsel$ssel" | grep -q , ; } || die "--run-id needs exactly one --task, one --strategy and --reps 1" 2
  trap on_interrupt INT TERM
  local names; names="$(if [ "$ssel" = all ]; then strategy_names; else echo "$ssel" | tr ',' ' '; fi)"
  rc=0
  for d in $(resolve_tasks "$tsel"); do
    for s in $names; do
      [ -f "$STRATS/$s.json" ] || die "unknown strategy $s" 2
      r=1
      while [ "$r" -le "$reps" ]; do
        t="$(task_id "$d")"
        if [ -n "$rid" ]; then id="$rid"
        elif [ -n "$prefix" ]; then id="$prefix-$t-$s-r$r"
        else id="$(date -u +%Y%m%dT%H%M%SZ)-$t-$s-r$r-$RANDOM"; fi
        run_one "$d" "$s" "$id"; rc=$?
        n=$((n + 1)); [ "$rc" = 130 ] || [ "$INTERRUPTED" = 1 ] && { echo "interrupted after $n runs"; exit 130; }
        r=$((r + 1))
      done
    done
  done
  echo "done: $n runs in $OUT/runs (SIMULATED: fixture data, harness validation only)"
}

# ---------- results ----------
scan_runs() {  # <results dir> -> prints "ok <id>", "tampered <id>", "incomplete <id>"
  local rd="$1/runs" d id
  [ -d "$rd" ] || return 0
  for d in "$rd"/*/; do
    [ -d "$d" ] || continue; d="${d%/}"; id="$(basename "$d")"
    if [ -f "$d/result.json" ]; then
      if [ -f "$d/result.sha256" ] && [ "$(sha_file "$d/result.json")" = "$(tr -d '[:space:]' < "$d/result.sha256")" ] \
         && jq -e '.schema == "tbench-result/1" and (.run_id == "'"$id"'")' "$d/result.json" >/dev/null 2>&1; then echo "ok $id"; else echo "tampered $id"; fi
    else echo "incomplete $id"; fi
  done
}
cmd_verify() {
  local dir="${1:-}" st id bad=0 n=0
  [ -d "$dir/runs" ] || die "no runs directory in '$dir'" 2
  while read -r st id; do
    n=$((n + 1)); echo "$st  $id"
    [ "$st" = tampered ] && bad=1
  done < <(scan_runs "$dir")
  echo "$n runs checked"
  [ $bad = 0 ] || exit 6
}
cmd_report() {
  local dir="" minn=5 json=0 write=1 integ files=() st id stamp base
  while [ $# -gt 0 ]; do
    case "$1" in --results) dir="$2"; shift ;; --min-n) minn="$2"; shift ;; --json) json=1 ;; --stdout-only) write=0 ;; *) usage ;; esac; shift
  done
  [ -d "$dir/runs" ] || die "no runs directory in '$dir'" 2
  case "$minn" in ''|*[!0-9]*|0) die "--min-n must be a positive integer" 2 ;; esac
  local tampered="" incomplete=""
  while read -r st id; do
    case "$st" in ok) files+=("$dir/runs/$id/result.json") ;; tampered) tampered="$tampered $id" ;; incomplete) incomplete="$incomplete $id" ;; esac
  done < <(scan_runs "$dir")
  integ="$(jq -n --arg t "$tampered" --arg i "$incomplete" '{tampered: ($t | split(" ") | map(select(. != ""))), incomplete: ($i | split(" ") | map(select(. != "")))}')"
  local rep
  if [ ${#files[@]} -gt 0 ]; then rep="$(jq -s --argjson min_n "$minn" --argjson integrity "$integ" -f "$LIB/report.jq" "${files[@]}")"
  else rep="$(jq -n --argjson min_n "$minn" --argjson integrity "$integ" '{schema:"tbench-report/1", runs_total:0, min_n:$min_n, integrity:$integrity, real:null, simulated:null, conclusions_allowed:false, notice:"No sealed runs."}')"; fi
  [ -n "$rep" ] || die "report calculation failed" 1
  if [ "$write" = 1 ]; then
    mkdir -p "$dir/reports"; stamp="$(date -u +%Y%m%dT%H%M%SZ)"; base="$dir/reports/report-$stamp"
    [ -e "$base.json" ] && base="$base-$$"
    printf '%s\n' "$rep" > "$base.json"; jq -r -f "$LIB/report-md.jq" <<< "$rep" > "$base.md"
    echo "wrote $base.json and $base.md" >&2
  fi
  if [ "$json" = 1 ]; then printf '%s\n' "$rep"; else jq -r -f "$LIB/report-md.jq" <<< "$rep"; fi
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  tasks) for d in $(task_dirs); do jq -r '"\(.id)@\(.version)\t\(.difficulty)\trisk=\(.risk)\t\(.title)"' "$d/task.json"; done ;;
  strategies) cmd_strategies ;;
  validate) cmd_validate "${1:-all}" ;;
  seal) cmd_seal "${1:-}" ;;
  fixtures) cmd_fixtures "${1:-all}" ;;
  run) cmd_run "$@" ;;
  preflight) cmd_preflight "$@" ;;
  ingest) cmd_ingest "$@" ;;
  verify) cmd_verify "${1:-}" ;;
  report) cmd_report "$@" ;;
  *) usage ;;
esac
