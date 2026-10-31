#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the file that was just written with the stack's formatter (stacks/<stack>/scripts/fmt.sh).
. "$(dirname "$0")/lib.sh"
path="$(jget .tool_input.file_path)"
[ -f "$path" ] || exit 0
fmt="$PROJECT_DIR/$KIT_DIR/scripts/fmt.sh"
[ -x "$fmt" ] || fmt="$PLUGIN_ROOT/stacks/$STACK/scripts/fmt.sh"
[ -x "$fmt" ] && "$fmt" "$path"
exit 0
