#!/usr/bin/env bash
# SubagentStop: when the verifier, reviewer or security-auditor agent finishes, record its VERDICT against the diff as it is now (F04: per role,
# with the host's agent_id as the run id; sdd.sh only trusts it if guard-budget.sh registered the spawn on this same diff).
# The workflow reads the verdict from here, never from what the implementing session claims. The block is validated and recorded by
# scripts/parse-verdict.sh --record (the one validation authority): a malformed or self-contradicting block records nothing and the
# orchestrator is told to ask the verifier for the exact format once. Never blocks, whatever happens.
. "$(dirname "$0")/lib.sh"
role="$(jget .agent_type)"; role="${role##*:}"; role="${role%-deep}"
case "$role" in verifier|reviewer|security-auditor) ;; *) exit 0 ;; esac
agent_id="$(jget .agent_id)"
msg="$(jget .last_assistant_message)"
if [ -z "$msg" ]; then  # fall back to the last text the agent wrote in its transcript
  transcript="$(jget .agent_transcript_path)"
  [ -f "$transcript" ] && msg="$(jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // empty' "$transcript" 2>/dev/null)"
fi
if [ -z "$msg" ]; then  # a stop with no answer (interrupted): its registration must not wait around for a later, different run to consume it
  [ -n "$agent_id" ] && [ -f "$PROJECT_DIR/$KIT_DIR/.sdd/state.json" ] && "$PLUGIN_ROOT/scripts/sdd.sh" _spawn-close --role "$role" --source hook >/dev/null 2>&1
  exit 0
fi
# the DoD items of the open task's proposal: the verifier must have judged every one of them
state="$PROJECT_DIR/$KIT_DIR/.sdd/state.json"; proposal=""
[ -f "$state" ] && proposal="$(jq -r '.proposal // empty' "$state" 2>/dev/null)"
args=(--role "$role" --source hook --record); [ -n "$agent_id" ] && args+=(--run "$agent_id")
[ "$role" = verifier ] && [ -n "$proposal" ] && [ -f "$PROJECT_DIR/$proposal" ] && args=(--proposal "$PROJECT_DIR/$proposal" "${args[@]}")
parse="$(kit_cmd "" scripts/parse-verdict.sh)"
summary="$(printf '%s\n' "$msg" | (cd "$PROJECT_DIR" && "$parse" - "${args[@]}") 2>&1)"
case $? in
  2) tele="$(kit_cmd "" scripts/telemetry.sh)"   # telemetry (TELEMETRY=1): a verdict that could not be recorded is a failure of its own kind
     if [ "${TELEMETRY:-}" = 1 ] && [ -x "$tele" ]; then
       "$tele" emit verify.result --outcome malformed --source verifier >/dev/null 2>&1
       "$tele" emit failure --category verdict-malformed --source verifier >/dev/null 2>&1
     fi
     case "$role" in verifier) fmt="DOD / FINDINGS / VERIFY / VERDICT" ;; reviewer) fmt="findings, SUMMARY and VERDICT" ;; *) fmt="findings, SUMMARY, NO FINDINGS (when empty) and VERDICT" ;; esac
     jq -n --arg m "$role verdict NOT recorded: $summary. Ask the $role once for the exact $fmt format." '{systemMessage:$m}' ;;
  3) jq -n --arg m "$role verdict NOT recorded as evidence: $summary. It does not count: run the $role again on the current diff." '{systemMessage:$m}' ;;
esac
exit 0
