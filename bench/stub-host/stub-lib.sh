# Shared by the stub hosts (sourced, not run). Sets $text, the step's fixture answer, after "doing the work" of the step.
#   fail/<step> exists   the host dies (exit 7), like a crashed or killed CLI
#   SDKIT_BENCH_CONTRACT=auto   the fixture acts like an agent that follows the handoff's contract: it ends the answer with a HANDOFF-RESULT
#                               line built from the prompt's ID: line, its role and the files the step wrote. Scenarios that test a broken
#                               contract do not use it; their answers/<step>.txt carry the line (or its flaw) by hand.
d="${SDKIT_BENCH_SCENARIO:?}"; step="${SDKIT_BENCH_STEP:?}"
if [ -f "$d/fail/$step" ]; then echo "stub host: simulated crash in step $step" >&2; exit 7; fi
[ -d "$d/sim/$step" ] && cp -R "$d/sim/$step/." .
text=done; [ -f "$d/answers/$step.txt" ] && text="$(cat "$d/answers/$step.txt")"
if [ "${SDKIT_BENCH_CONTRACT:-}" = auto ]; then
  _all="$(printf '%s\n' "$@")"
  _id="$(printf '%s\n' "$_all" | sed -n 's/^ID: *//p' | head -1)"
  _role="$(printf '%s\n' "$_all" | sed -n 's/^You are running as the "\([^"]*\)" role.*/\1/p' | head -1)"
  _arts=none; [ -d "$d/sim/$step" ] && _arts="$(cd "$d/sim/$step" && find . -type f | sed 's#^\./##' | sort | paste -sd, -)"
  [ -n "$_id" ] && text="$text"$'\n'"HANDOFF-RESULT/1 | id: $_id | role: $_role | status: done | artifacts: $_arts | blockers: none | next: -"
fi
