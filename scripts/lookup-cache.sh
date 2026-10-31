#!/usr/bin/env bash
# Answers to scout lookups ("where is X defined", "who calls Y"), kept for the task so the same question is not paid for twice.
# An answer is valid only for the exact code state it was given for: it is dropped when HEAD or the working-tree diff has changed.
# Files: <project-dir>/work/<slug>/lookups/<key>.md (personal, gitignored).
#   lookup-cache.sh get <slug> <question>     print the cached answer; exit 1 on a miss (nothing cached, or the code moved on)
#   lookup-cache.sh put <slug> <question>     store the answer read from stdin
#   lookup-cache.sh clear <slug>              forget the task's lookups
set -u
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "lookup-cache.sh needs a git repository" >&2; exit 1; }
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_resolve_dir "$top"
cmd="${1:-}"; slug="${2:-}"
[ -n "$cmd" ] && [ -n "$slug" ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "$slug" in *[!A-Za-z0-9_.-]*) echo "slug may contain letters, digits, _ . - only" >&2; exit 2 ;; esac
dir="$top/$KIT_DIR/work/$slug/lookups"
hash() { if command -v shasum >/dev/null; then shasum; else sha1sum; fi | cut -c1-40; }
# lowercase and collapse whitespace so trivial rewording of the same question still hits
key() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//' | hash; }
# code state: HEAD, a hash of the uncommitted diff, and the name and content of every untracked file (the same inputs verify-core.sh keys its
# green-result cache on; git diff alone does not see a new file). The kit's own work files are left out, or writing an answer would stale it.
untracked() { git -C "$top" ls-files -o --exclude-standard -- . ":!$KIT_DIR/work" ":!$KIT_DIR/.sdd" ":!$KIT_DIR/.verify-cache" 2>/dev/null |
  while IFS= read -r f; do printf '%s\n' "$f"; [ -f "$top/$f" ] && hash < "$top/$f"; done | hash; }
state() { printf '%s %s %s' "$(git -C "$top" rev-parse HEAD 2>/dev/null)" "$(git -C "$top" diff HEAD 2>/dev/null | hash)" "$(untracked)"; }
case "$cmd" in
  get)
    f="$dir/$(key "${3:-}").md"; [ -f "$f" ] || exit 1
    [ "$(head -1 "$f")" = "state: $(state)" ] || { rm -f "$f"; exit 1; }
    tail -n +2 "$f" ;;
  put)
    [ -n "${3:-}" ] || exit 2
    mkdir -p "$dir"; { echo "state: $(state)"; cat; } > "$dir/$(key "$3").md" ;;
  clear) rm -rf "$dir" ;;
  *) exit 2 ;;
esac
