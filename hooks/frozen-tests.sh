#!/usr/bin/env bash
# PreToolUse(Edit|Write): deny edits to files listed in <project-dir>/.frozen (one repo-relative path per line).
# spec-driven-dev role [A] appends the regression test here so the implementer cannot weaken it.
. "$(dirname "$0")/lib.sh"
frozen_file="$PROJECT_DIR/$KIT_DIR/.frozen"
[ -f "$frozen_file" ] || exit 0
path="$(jget .tool_input.file_path)"
if type sdkit_relpath >/dev/null 2>&1; then rel="$(sdkit_relpath "$PROJECT_DIR" "$path")"; else rel="${path#"$PROJECT_DIR"/}"; fi   # ./x, a/../x and // resolve first
grep -qxF "$rel" "$frozen_file" && \
  decide deny "'$rel' is frozen by spec-driven-dev. Fix the implementation, not the test."
exit 0
