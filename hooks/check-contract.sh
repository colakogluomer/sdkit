#!/usr/bin/env bash
# Agent contracts (scripts/contract.sh). Off unless CONTRACTS=1 in sdkit.env. Two events, one script:
#   PreToolUse on the Agent tool: a prompt that carries a `CONTRACT:` line is a contracted handoff; it is validated and registered before the agent
#     starts. An invalid one asks first in strict mode (a spawn that cannot produce a valid result costs tokens), only warns in guided mode.
#   SubagentStop: the agent's last message is checked for its HANDOFF-RESULT line. A contract problem is reported to the orchestrator, once;
#     it never blocks and never touches the verdict (record-verdict.sh / parse-verdict.sh stay the only authority for the verifier).
# A prompt or answer without any contract is legacy and passes silently, unless the task's profile requires contracts (high-assurance,
# scripts/workflow.sh): then a spawn of a kit role without one asks first (strict) / warns (guided). Never blocks because of its own problem.
. "$(dirname "$0")/lib.sh"
if [ "${CONTRACTS:-}" != 1 ]; then   # off, unless the open task runs a profile that requires contracts (a file read, no process)
  grep -qs 'high-assurance' "$PROJECT_DIR/$KIT_DIR/.sdd/state.json" || exit 0
fi
c="$(kit_cmd "" scripts/contract.sh)"; [ -x "$c" ] || exit 0
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
case "$(jget .hook_event_name)" in
  PreToolUse)
    prompt="$(jget .tool_input.prompt)"
    role="$(jget .tool_input.subagent_type)"
    if ! printf '%s\n' "$prompt" | grep -qE '^[[:space:]]*CONTRACT:'; then
      wf="$(kit_cmd "" scripts/workflow.sh)"; [ -x "$wf" ] || exit 0
      reason="$("$wf" require --role "$role" --boundary agent --marker no 2>/dev/null)" || {
        mode="$("$PLUGIN_ROOT/scripts/sdd.sh" mode 2>/dev/null)"
        [ "$mode" = off ] && exit 0
        [ "$mode" = guided ] && { jq -n --arg m "$reason" '{systemMessage:$m}'; exit 0; }
        decide ask "$reason"; }
      exit 0
    fi
    summary="$(printf '%s\n' "$prompt" | "$c" issue - ${role:+--role "$role"} --source hook 2>&1)"
    [ $? = 2 ] || exit 0
    mode="$("$PLUGIN_ROOT/scripts/sdd.sh" mode 2>/dev/null)"
    reason="Handoff contract rejected: $summary. Fix the handoff (references/contract.md) before spawning."
    [ "$mode" = off ] && exit 0
    [ "$mode" = guided ] && { jq -n --arg m "$reason" '{systemMessage:$m}'; exit 0; }
    decide ask "$reason" ;;
  SubagentStop)
    msg="$(jget .last_assistant_message)"
    if [ -z "$msg" ]; then
      transcript="$(jget '.agent_transcript_path // .transcript_path')"
      [ -f "$transcript" ] && msg="$(jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // empty' "$transcript" 2>/dev/null)"
    fi
    role="$(jget '.agent_type // .subagent_type')"; role="${role##*:}"
    summary="$(printf '%s\n' "$msg" | (cd "$PROJECT_DIR" && "$c" check-result - ${role:+--role "$role"} --cwd "$PROJECT_DIR" --record --legacy-ok --source hook) 2>&1)"
    case $? in
      2) jq -n --arg m "Agent contract NOT accepted: $summary. Ask the agent once for the HANDOFF-RESULT line (state.sh <slug> retry <id> first); a contract never replaces the verifier." '{systemMessage:$m}' ;;
    esac ;;
esac
exit 0
