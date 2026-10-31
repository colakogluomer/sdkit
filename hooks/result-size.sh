#!/usr/bin/env bash
# SubagentStop: warn when a role's final answer is longer than SUBAGENT_RESULT_MAX_LINES (the handoff asks for a short summary plus
# the structured block; the full text belongs in a file under work/<slug>/out/). Off unless the setting is a positive integer. Never blocks.
. "$(dirname "$0")/lib.sh"
case "${SUBAGENT_RESULT_MAX_LINES:-}" in ''|*[!0-9]*|0) exit 0 ;; esac
text="$(jget .last_assistant_message)"
if [ -z "$text" ]; then
  transcript="$(jget '.agent_transcript_path // .transcript_path')"; [ -f "$transcript" ] || exit 0
  text="$(jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // empty' "$transcript" 2>/dev/null)"
fi
[ -n "$text" ] || exit 0
lines="$(printf '%s\n' "$text" | wc -l | tr -d ' ')"
[ "$lines" -gt "$SUBAGENT_RESULT_MAX_LINES" ] || exit 0
role="$(jget '.agent_type // .subagent_type')"; role="${role##*:}"
jq -n --arg m "${role:-subagent} returned $lines lines (limit $SUBAGENT_RESULT_MAX_LINES). Ask it for a short summary and have it write the full text under work/<slug>/out/ (handoff field OUT)." '{systemMessage:$m}'
exit 0
