#!/usr/bin/env bash
# PreToolUse(Edit|Write): ask before touching PROTECTED_PATHS.
. "$(dirname "$0")/lib.sh"
path="$(jget .tool_input.file_path)"
[ -z "$path" ] && exit 0
if type sdkit_relpath >/dev/null 2>&1; then rel="$(sdkit_relpath "$PROJECT_DIR" "$path")"; else rel="${path#"$PROJECT_DIR"/}"; fi   # ./x, a/../x and // resolve first
IFS=',' read -r -a protected <<< "${PROTECTED_PATHS:-}"
for prefix in "${protected[@]}"; do
  [ -n "$prefix" ] && case "$rel" in "$prefix"/*) \
    decide ask "'$prefix' is listed in PROTECTED_PATHS ($KIT_DIR/$KIT_ENV). Check project.md for when it may be changed." ;; esac
done
exit 0
