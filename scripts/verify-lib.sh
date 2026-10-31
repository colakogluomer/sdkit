# Helpers for verify policies. Source this; the runner skips files starting with "_".
# The engine exports VERIFY_ROOT, VERIFY_MERGE_BASE, VERIFY_CHANGED and VERIFY_CHANGED_GO before running a policy.

# added_lines <pathspec...>: lines added since VERIFY_MERGE_BASE, prefixed with "+".
# git diff does not show untracked files, so their full content counts as added.
added_lines() {
  git diff -U0 "$VERIFY_MERGE_BASE" -- "$@" | grep '^+[^+]' || true
  for f in $(git ls-files -o --exclude-standard -- "$@"); do
    [ -f "$f" ] && sed 's/^/+/' "$f"
  done
}
