#!/usr/bin/env bash
# PreToolUse(Bash): push and PR creation need a verified task whose diff is unchanged since (scripts/sdd.sh gate push).
# Also keeps the model away from the workflow state and the hook-only verdict/evidence/spawn commands.
. "$(dirname "$0")/lib.sh"
command="$(jget .tool_input.command)"
[ -z "$command" ] && exit 0
sdd="$(kit_cmd "" scripts/sdd.sh)"
mode="$("$sdd" mode)"
[ "$mode" = off ] && exit 0

printf '%s' "$command" | grep -qE '\.sdd/|attestations/|sdd\.sh[^;&|]* _(verdict|evidence|spawn)|hooks/(record-verdict|guard-budget)\.sh' && \
  decide deny "The workflow state and verdicts are written only by sdd.sh and the verifier hook, never by hand."
# Claude Code records the verdict in the SubagentStop hook (record-verdict.sh), so recording by hand there would be forging one.
# Hosts without that hook (adapt.sh and the OpenCode plugin set SDKIT_HOST) record with parse-verdict.sh --record, which validates the block first.
[ -z "${SDKIT_HOST:-}" ] && printf '%s' "$command" | grep -qE 'parse-verdict\.sh[^;&|]*--record' && \
  decide deny "On Claude Code the verifier hook records the verdict. Run parse-verdict.sh without --record to check the block."

printf '%s' "$command" | grep -qE '(^|[;&|] *)(git +push|gh +pr +create|glab +mr +create|[^ ]*open-pr\.sh)' || exit 0
reason="$("$sdd" gate push)" && exit 0
[ "$mode" = strict ] && decide deny "$reason" || decide ask "$reason"
