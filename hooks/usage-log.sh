#!/usr/bin/env bash
# SubagentStop / Stop: append token usage from the transcript to the ledger (scripts/usage.sh) and, with TELEMETRY=1, an agent.end event
# (scripts/telemetry.sh). Off unless USAGE_LOG=1 or TELEMETRY=1. Never blocks: any problem (no transcript, unexpected shape) is a silent exit 0.
. "$(dirname "$0")/lib.sh"
[ "${USAGE_LOG:-}" = 1 ] || [ "${TELEMETRY:-}" = 1 ] || exit 0
event="$(jget .hook_event_name)"
if [ "$event" = SubagentStop ]; then
  transcript="$(jget '.agent_transcript_path // .transcript_path')"; role="$(jget '.agent_type // .subagent_type')"; role="${role##*:}"
  id="$(jget '.agent_id // empty')"
else
  transcript="$(jget .transcript_path)"; role=orchestrator; id="session-$(jget .session_id)"
fi
[ -f "$transcript" ] || exit 0
[ -n "$role" ] || role=subagent
# one line per assistant message id (streamed transcripts repeat it), summed
totals="$(jq -rs '[ .[] | select(.type=="assistant") | .message | select(.usage) | {id, u:.usage} ] | unique_by(.id)
  | {i:(map(.u.input_tokens // 0)|add // 0), o:(map(.u.output_tokens // 0)|add // 0),
     cr:(map(.u.cache_read_input_tokens // 0)|add // 0), cw:(map(.u.cache_creation_input_tokens // 0)|add // 0)}
  | "\(.i) \(.o) \(.cr) \(.cw)"' "$transcript" 2>/dev/null)" || exit 0
set -- $totals; [ $# -eq 4 ] || exit 0
model="$(jq -rs '[.[] | select(.type=="assistant") | .message.model // empty] | last // empty' "$transcript" 2>/dev/null)"
if [ "${TELEMETRY:-}" = 1 ]; then
  # tool calls are counted from the transcript (actual); the duration is the span between its first and last timestamp (estimated: the
  # agent may have waited before its first line). A Stop snapshot and a SubagentStop for the same span replace each other in the summary.
  extra="$(jq -rs '{tc: ([.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .id] | unique | length),
      ts: ([.[] | .timestamp? // empty | select(type=="string") | sub("\\.[0-9]+";"") | try fromdateiso8601 catch empty] | if length > 1 then (max - min) * 1000 else null end)}
    | "\(.tc) \(.ts // "")"' "$transcript" 2>/dev/null)"
  set -- $totals; i="$1"; o="$2"; cr="$3"; cw="$4"; set -- $extra
  tele="$(kit_cmd "" scripts/telemetry.sh)"
  [ -x "$tele" ] && "$tele" emit agent.end --role "$role" --host claude --model "${model:-}" --in "$i" --out "$o" --cache-read "$cr" --cache-write "$cw" \
    --tool-calls "${1:-}" --dur-ms "${2:-}" --q tokens=actual --q tool_calls=actual --q duration=estimated ${id:+--span "$id"} --source "$event" >/dev/null 2>&1
  set -- $totals
fi
script="$(kit_cmd "" "scripts/usage.sh")"; [ -x "$script" ] || script="$PROJECT_DIR/$KIT_DIR/scripts/usage.sh"
[ -x "$script" ] || exit 0
"$script" log --role "$role" --host claude --model "${model:-}" --in "$1" --out "$2" --cache-read "$3" --cache-write "$4" \
  ${id:+--id "$id"} --source "$event" >/dev/null 2>&1
exit 0
