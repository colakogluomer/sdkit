#!/usr/bin/env bash
# Shared verify engine. Source it from a stack's verify.sh; do not run it directly.
#
#   verify.sh [--fast] [--since-head] [--no-cache]
#     --fast        cheap checks only (what the stack calls fast: vet+build, typecheck, compile ...)
#     --since-head  only uncommitted changes (used by the Stop hook), not the whole branch
#     --no-cache    ignore the green-result cache
#
# A stack provides steps.sh, sourced after this file, defining:
#   STACK_SOURCE_RE   ERE matching the stack's source files in $CHANGED (e.g. '\.go$')
#   stack_run         runs the stack's checks; uses FAST, CHANGED, CHANGED_SRC, MERGE_BASE, and fail/warn/step
# and calls verify_main as its last line. Project policy in ${VERIFY_POLICY_DIR:-<project-dir>/verify.d}/*.sh runs after
# the stack checks (one check per file; prints "FAIL: ..." or "WARN: ..."; files starting with "_" are helpers).
#
# A green result is cached per exact tree (HEAD + diff + untracked content + flags + policies + sdkit.env), so the Stop hook,
# the verifier and the PR step do not repeat the same work. Failures are never cached.
set -u

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1
# project dir: .sdkit (or a legacy .agentkit, .claude, .codex), whichever holds sdkit.env or the old project.env (KIT_DIR overrides)
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$ROOT"; export KIT_DIR
BASE_BRANCH="${BASE_BRANCH:-develop}"

FAILURES=0
WARNINGS=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo "  WARN: $*"; WARNINGS=$((WARNINGS + 1)); }
step() { echo "==> $*"; }

# the first executable resolve-base.sh: DIFF_BASE_CMD (project-relative), next to the engine, or the kit's scripts/ directory
_core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="${ENGINE_DIR:-$_core_dir}"

_verify_setup() {
  FAST=0; SINCE_HEAD=0; NO_CACHE=0
  for arg in "$@"; do
    case "$arg" in
      --fast) FAST=1 ;;
      --since-head) SINCE_HEAD=1 ;;
      --no-cache) NO_CACHE=1 ;;
    esac
  done
  local candidate RESOLVE_BASE=""
  for candidate in "${DIFF_BASE_CMD:+$ROOT/$DIFF_BASE_CMD}" "$ENGINE_DIR/resolve-base.sh" "$_core_dir/resolve-base.sh" "$ENGINE_DIR/../../../scripts/resolve-base.sh"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { RESOLVE_BASE="$candidate"; break; }
  done
  if [ -n "$RESOLVE_BASE" ]; then BASE_REF="$("$RESOLVE_BASE")"
  else
    BASE_REF="origin/$BASE_BRANCH"
    git rev-parse --verify -q "$BASE_REF" >/dev/null || BASE_REF="$BASE_BRANCH"
  fi
  MERGE_BASE="$(git merge-base "$BASE_REF" HEAD 2>/dev/null || echo HEAD)"
  [ "$SINCE_HEAD" = 1 ] && MERGE_BASE=HEAD
  CHANGED="$( { git diff --name-only "$MERGE_BASE"; git ls-files -o --exclude-standard; } | sort -u)"
  CHANGED_SRC="$(printf '%s\n' "$CHANGED" | grep -E "${STACK_SOURCE_RE:-^\$}" || true)"
}

_verify_policies() {
  export VERIFY_ROOT="$ROOT" VERIFY_MERGE_BASE="$MERGE_BASE" VERIFY_CHANGED="$CHANGED" VERIFY_CHANGED_SRC="$CHANGED_SRC"
  [ "$STACK" = go ] && export VERIFY_CHANGED_GO="$CHANGED_SRC"
  export VERIFY_LIB="$ENGINE_DIR/verify-lib.sh"
  [ -f "$VERIFY_LIB" ] || VERIFY_LIB="$_core_dir/verify-lib.sh"; export VERIFY_LIB
  local policy output status line
  for policy in "${VERIFY_POLICY_DIR:-$KIT_DIR/verify.d}"/[!_]*.sh; do
    [ -x "$policy" ] || continue
    step "policy $(basename "$policy" .sh)"
    output="$("$policy" 2>&1)"; status=$?
    [ -n "$output" ] && echo "$output"
    while IFS= read -r line; do
      case "$line" in
        "FAIL: "*) FAILURES=$((FAILURES + 1)) ;;
        "WARN: "*) WARNINGS=$((WARNINGS + 1)) ;;
      esac
    done <<< "$output"
    if [ "$status" -ne 0 ] && ! echo "$output" | grep -q '^FAIL: '; then fail "policy $(basename "$policy") exited $status"; fi
  done
}

_verify_body() {
  stack_run
  _verify_policies
  echo
  echo "verify: $FAILURES failure(s), $WARNINGS warning(s)"
  [ "$FAILURES" -eq 0 ]
}

# cache key for the exact state of the tree and the flags
_verify_key() {
  {
    echo "core1 $STACK fast=$FAST since=$SINCE_HEAD base=$MERGE_BASE"
    git rev-parse HEAD 2>/dev/null
    git diff HEAD 2>/dev/null
    git ls-files -o --exclude-standard | while IFS= read -r f; do printf '%s\n' "$f"; [ -f "$f" ] && shasum "$f"; done
    cat "$KIT_DIR/$KIT_ENV" "$KIT_DIR/sdkit.local.env" 2>/dev/null
    for p in "${VERIFY_POLICY_DIR:-$KIT_DIR/verify.d}"/[!_]*.sh; do [ -f "$p" ] && { echo "$p"; cat "$p"; }; done
  } | shasum | cut -d' ' -f1
}

verify_main() {
  _verify_setup "$@"
  [ -z "$CHANGED" ] && { echo "nothing changed vs $BASE_REF"; exit 0; }
  local cache_dir="$ROOT/$KIT_DIR/.verify-cache" key="" out rc
  if [ "$NO_CACHE" = 0 ]; then
    key="$(_verify_key)"
    if [ -f "$cache_dir/$key" ]; then cat "$cache_dir/$key"; echo "(cached: identical tree already verified green)"; exit 0; fi
  fi
  out="$(mktemp)"; trap 'rm -f "$out"' EXIT
  _verify_body > "$out" 2>&1; rc=$?
  cat "$out"
  if [ "$rc" = 0 ] && [ -n "$key" ]; then
    mkdir -p "$cache_dir" && cp "$out" "$cache_dir/$key"
    # keep only the 20 most recent entries
    ls -t "$cache_dir" 2>/dev/null | tail -n +21 | while IFS= read -r old; do rm -f "$cache_dir/$old"; done
  fi
  exit "$rc"
}
