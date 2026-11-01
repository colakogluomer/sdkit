#!/usr/bin/env bash
# SessionEnd / SessionStart: the Value Report's session level (scripts/report.sh). Off unless VALUE_REPORT=on. Never blocks and never prints on stdout
# (a SessionStart hook's stdout would enter the model context): any problem is a silent exit 0.
#   SessionEnd   a true end-of-session signal: mark the session ended and store its summary (reason from the host: clear, logout, prompt_input_exit, other ...)
#   SessionStart earlier sessions that left records but never got an end signal (killed, crashed) get a summary marked "interrupted"
. "$(dirname "$0")/lib.sh"
[ "${VALUE_REPORT:-}" = on ] || exit 0
event="$(jget .hook_event_name)"; session="$(jget '.session_id // empty')"
script="$(kit_cmd "" "scripts/report.sh")"; [ -x "$script" ] || script="$PROJECT_DIR/$KIT_DIR/scripts/report.sh"
[ -x "$script" ] || exit 0
case "$event" in
  SessionEnd) [ -n "$session" ] && "$script" session-end --session "$session" --reason "$(jget '.reason // empty')" >&2 2>&1 ;;
  SessionStart) "$script" recover ${session:+--session "$session"} >&2 2>&1 ;;
esac
exit 0
