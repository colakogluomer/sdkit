#!/usr/bin/env bash
# Host-independent guards for git hooks and CI. Same rules as the Claude Code hooks, enforced at commit/push time
# so they hold for any agent (Codex, Cursor, a human).
# Usage: guard.sh pre-commit | pre-push [remote] [url]     (run from a git hook; reads stdin refs on pre-push)
# Overrides (deliberate, per command): ALLOW_PROTECTED=1  ALLOW_PROTECTED_PUSH=1  GUARD_SKIP_VERIFY=1
set -u
top="$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$top"
export KIT_DIR
fail=0
sdd="$(cd "$(dirname "$0")" && pwd)/sdd.sh"
# spec-driven phase gate: strict blocks, guided warns (a git hook cannot ask), off skips. SDD_SKIP=1 bypasses once, on purpose.
sdd_gate() { # <gate args...>
  [ "${SDD_SKIP:-0}" = 1 ] && return 0
  [ -x "$sdd" ] || return 0
  local mode reason; mode="$("$sdd" mode)"; [ "$mode" = off ] && return 0
  reason="$("$sdd" gate "$@")" && return 0
  if [ "$mode" = strict ]; then bad "$reason (SDD_SKIP=1 bypasses once)"; else echo "guard (warning): $reason" >&2; fi
}
bad() { echo "guard: $*" >&2; fail=1; }

matches_glob_list() { # <path> <comma globs>
  local path="$1" glob base patterns; base="$(basename "$path")"
  # read into an array: an unquoted `for glob in $2` would expand the patterns against the files in the current directory
  [ -n "$2" ] || return 1   # (bash 3.2 + set -u: an empty array expansion is an error)
  IFS=',' read -r -a patterns <<< "$2"
  for glob in "${patterns[@]}"; do
    [ -z "$glob" ] && continue
    case "$base" in $glob) return 0 ;; esac
    case "$path" in $glob) return 0 ;; esac
  done
  return 1
}

case "${1:-}" in
  pre-commit)
    staged="$(git diff --cached --name-only --diff-filter=ACMR)"
    frozen=""; [ -f "$top/$KIT_DIR/.frozen" ] && frozen="$(cat "$top/$KIT_DIR/.frozen")"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      sdd_gate edit "$f"
      matches_glob_list "$f" "${SECRET_GLOBS:-}" && bad "'$f' matches SECRET_GLOBS; secrets must not be committed."
      [ -n "$frozen" ] && printf '%s\n' "$frozen" | grep -qxF "$f" && bad "'$f' is a frozen test ($KIT_DIR/.frozen); fix the implementation, not the test."
      if [ -n "${PROTECTED_PATHS:-}" ] && [ "${ALLOW_PROTECTED:-0}" != 1 ]; then
        IFS=',' read -r -a prefixes <<< "$PROTECTED_PATHS"
        for p in "${prefixes[@]}"; do
          [ -z "$p" ] && continue
          case "$f" in "$p"*) bad "'$f' is under protected path '$p' (see $KIT_DIR/project.md). Re-run with ALLOW_PROTECTED=1 once you have approval." ;; esac
        done
      fi
    done <<< "$staged"
    ;;
  pre-push)
    sdd_gate push
    if [ -n "${PROTECTED_BRANCHES:-}" ] && [ "${ALLOW_PROTECTED_PUSH:-0}" != 1 ]; then
      while read -r _ _ remote_ref _; do
        b="${remote_ref#refs/heads/}"
        matches_glob_list "$b" "$PROTECTED_BRANCHES" && bad "push to protected branch '$b' needs approval. Re-run with ALLOW_PROTECTED_PUSH=1."
      done
    fi
    if [ "$fail" = 0 ] && [ "${GUARD_SKIP_VERIFY:-0}" != 1 ]; then
      v="${VERIFY_CMD:-}"
      if [ -n "$v" ]; then v="$top/$v"
      elif [ -x "$top/$KIT_DIR/scripts/verify.sh" ]; then v="$top/$KIT_DIR/scripts/verify.sh"
      else v="$(cd "$(dirname "$0")/.." && pwd)/stacks/$STACK/scripts/verify.sh"; fi
      if [ -x "$v" ]; then
        out="$("$v" --fast --since-head 2>&1)" || { printf '%s\n' "$out" | tail -30 >&2; bad "verify (vet/build) is red; fix it before pushing (GUARD_SKIP_VERIFY=1 to bypass deliberately)."; }
      fi
    fi
    ;;
  *) echo "usage: guard.sh pre-commit|pre-push" >&2; exit 2 ;;
esac
exit "$fail"
