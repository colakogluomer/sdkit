#!/usr/bin/env bash
# Run one of the kit's Claude-shaped hooks for another host.
# Usage (host hook config): adapt.sh <gemini|cursor> <hook-script>      host JSON on stdin
#   1. rewrites the host's tool-call JSON into the shape the hooks read ({tool_name, tool_input.{file_path,command}})
#   2. runs the hook unchanged
#   3. turns its permissionDecision into the host's deny protocol
#      gemini: deny -> exit 2 + reason on stderr.   cursor: deny/ask -> {"permission":...} (ask only where Cursor supports it).
# A host without "ask" gets a deny whose reason says an explicit approval is needed. Exit 0 with no output = allow.
host="${1:-}"; script="${2:-}"
[ -f "$script" ] || { [ -f "$(dirname "$0")/$script" ] && script="$(dirname "$0")/$script"; }
[ -f "$script" ] || exit 0
in="$(cat)"
j() { printf '%s' "$in" | jq -r "$1 // empty" 2>/dev/null; }

event="$(j '.hook_event_name')"
tool="$(j '.tool_name')"; path=""; cmd=""
case "$host" in
  gemini)
    case "$tool" in
      read_file|read_many_files) tool=Read ;;
      write_file) tool=Write ;;
      replace) tool=Edit ;;
      run_shell_command) tool=Bash ;;
      *) exit 0 ;;
    esac
    path="$(j '.tool_input.file_path // .tool_input.absolute_path // .tool_input.path')"
    cmd="$(j '.tool_input.command')" ;;
  cursor)
    case "$event" in
      beforeShellExecution) tool=Bash; cmd="$(j '.command')" ;;
      beforeReadFile) tool=Read; path="$(j '.file_path')" ;;
      afterFileEdit) tool=Edit; path="$(j '.file_path')" ;;
      *)
        case "$tool" in
          Shell) tool=Bash ;; Read) ;; Write) ;; Delete) tool=Write ;; *) exit 0 ;;
        esac
        path="$(j '.tool_input.file_path // .tool_input.path')"; cmd="$(j '.tool_input.command')" ;;
    esac ;;
  *) echo "adapt.sh: unknown host '$host'" >&2; exit 0 ;;
esac

root="${CURSOR_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(j '.workspace_roots[0] // .cwd')}}"
[ -n "$root" ] && [ -d "$root" ] && export CLAUDE_PROJECT_DIR="$root"
sub="$(j '.subagent_type // .agent_type')"
norm="$(jq -n --arg t "$tool" --arg p "$path" --arg c "$cmd" --arg a "$sub" \
  '{tool_name:$t, tool_input:{file_path:$p, command:$c}, agent_type:$a}')"

out="$(printf '%s' "$norm" | SDKIT_HOST="$host" bash "$script" 2>/dev/null)" || true
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
case "$dec" in
  deny|ask) ;;
  *) exit 0 ;;
esac
case "$host" in
  gemini)
    [ "$dec" = ask ] && reason="needs explicit approval: $reason"
    echo "$reason" >&2; exit 2 ;;
  cursor)
    if [ "$dec" = ask ] && [ "$event" = beforeShellExecution ]; then
      jq -n --arg r "$reason" '{permission:"ask", user_message:$r, agent_message:$r}'
    else
      [ "$dec" = ask ] && reason="needs explicit approval: $reason"
      jq -n --arg r "$reason" '{permission:"deny", user_message:$r, agent_message:$r}'
    fi ;;
esac
exit 0
