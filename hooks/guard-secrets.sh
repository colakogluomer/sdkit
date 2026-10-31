#!/usr/bin/env bash
# PreToolUse(Read|Edit|Write): deny access to files matching SECRET_GLOBS.
. "$(dirname "$0")/lib.sh"
path="$(jget .tool_input.file_path)"
[ -z "$path" ] && exit 0
matches_glob_list "$path" "${SECRET_GLOBS:-}" && \
  decide deny "'$path' matches SECRET_GLOBS in $KIT_DIR/$KIT_ENV. Secrets must not be read or written by the agent."
exit 0
