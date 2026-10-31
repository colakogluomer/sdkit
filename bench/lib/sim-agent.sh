#!/usr/bin/env bash
# SIMULATION ONLY. The stand-in "development agent" of `tbench.sh run --simulate`: no model, no network. It runs inside the task workspace with the
# scrubbed environment the harness gives every agent and acts out one outcome (SDKIT_TBENCH_SIM_VARIANT):
#   reference|partial  copy the staged solution files in     starter  change nothing     tests-only  rewrite the visible tests only
#   crash  exit 9     hang  never finish (timeout path)      flood  print without end (output-limit path)
# Afterwards it leaves the metrics a real strategy adapter would leave (copied from the staged fixture) in $SDKIT_TBENCH_OUT.
set -u
echo "sim-agent: SIMULATED run=${SDKIT_TBENCH_RUN_ID:-?} strategy=${SDKIT_TBENCH_STRATEGY:-?} variant=${SDKIT_TBENCH_SIM_VARIANT:-?}"
echo "--- environment visible to the agent ---"; env | sort; echo "--- end environment ---"
case "${SDKIT_TBENCH_SIM_VARIANT:-starter}" in
  reference|partial) cp -R "${SDKIT_TBENCH_PAYLOAD:?}/." . ;;
  starter) : ;;
  tests-only) printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ok(self):\n        pass\n' > tests/test_public.py ;;
  crash) echo "sim-agent: simulated crash" >&2; exit 9 ;;
  hang) sleep 600 ;;
  flood) yes "simulated runaway output" | head -c 50000000 ;;
  *) echo "sim-agent: unknown variant" >&2; exit 2 ;;
esac
if [ -d "${SDKIT_TBENCH_SIM_SRC:-/nonexistent}" ]; then
  for f in "$SDKIT_TBENCH_SIM_SRC"/*; do [ -f "$f" ] && cp "$f" "${SDKIT_TBENCH_OUT:?}/"; done
fi
exit 0
