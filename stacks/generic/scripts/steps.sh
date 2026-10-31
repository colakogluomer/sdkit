# Stack-less checks for the shared verify engine (scripts/verify-core.sh). Sourced by verify.sh; do not run directly.
# The project supplies its own commands in sdkit.env (run from the repo root):
#   VERIFY_FAST_CMD   cheap check (typecheck, compile, lint); runs for --fast and for the full verify
#   VERIFY_TEST_CMD   tests; full verify only
STACK_SOURCE_RE='.'

stack_run() {
  if [ -n "${VERIFY_FAST_CMD:-}" ]; then
    step "fast check"
    (cd "$ROOT" && bash -c "$VERIFY_FAST_CMD" 2>&1) || fail "VERIFY_FAST_CMD"
  fi
  [ "$FAST" = 1 ] && return 0
  if [ -n "${VERIFY_TEST_CMD:-}" ]; then
    step "tests"
    (cd "$ROOT" && bash -c "$VERIFY_TEST_CMD" 2>&1) || fail "VERIFY_TEST_CMD"
  fi
  [ -n "${VERIFY_FAST_CMD:-}${VERIFY_TEST_CMD:-}" ] || warn "no VERIFY_FAST_CMD / VERIFY_TEST_CMD set in sdkit.env, nothing was checked (only verify.d policies ran)"
}
