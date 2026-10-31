#!/usr/bin/env bash
# PreToolUse(Bash|Edit|Write): a read-only role (reviewer, verifier, ...) must not change files.
# The role is the subagent the call comes from (agent_type in the hook input); a role is read-only when its agent file
# lists no Edit/Write tool. No agent_type in the input (older hosts, main session) = off, silently.
. "$(dirname "$0")/lib.sh"
type="$(jget '.agent_type // .subagent_type')"
[ -z "$type" ] && exit 0
name="${type##*:}"
file="$PROJECT_DIR/.claude/agents/$name.md"
[ -f "$file" ] || file="$PLUGIN_ROOT/agents/$name.md"
[ -f "$file" ] || exit 0
grep -m1 '^tools:' "$file" | grep -qE 'Edit|Write' && exit 0

tool="$(jget .tool_name)"
case "$tool" in
  Edit|Write|NotebookEdit) decide deny "'$name' is a read-only role: it cannot edit files. Report the finding instead." ;;
  Bash) ;;
  *) exit 0 ;;
esac

cmd="$(jget .tool_input.command)"
# harmless redirections first, then any remaining '>' writes a file
scrubbed="$(printf '%s' "$cmd" | sed -E 's/[0-9&]?>+[[:space:]]*\/dev\/null//g; s/[0-9]>&[0-9]//g')"
case "$scrubbed" in *">"*) decide deny "'$name' is read-only: output redirection to a file is not allowed." ;; esac
# every command in a pipeline / list
segments="$(printf '%s' "$scrubbed" | sed -E 's/(&&|\|\||;|\|)/\n/g')"
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^(env |sudo |command |time )//')"
  [ -z "$seg" ] && continue
  case "$seg" in
    rm\ *|rmdir\ *|mv\ *|cp\ *|mkdir\ *|touch\ *|chmod\ *|chown\ *|ln\ *|tee\ *|dd\ *|truncate\ *|install\ *|patch\ *)
      decide deny "'$name' is read-only: '${seg%% *}' changes files." ;;
    sed\ *-i*|perl\ *-i*|sed\ -[a-zA-Z]*i*)
      decide deny "'$name' is read-only: in-place edit is not allowed." ;;
    git\ add*|git\ commit*|git\ checkout*|git\ switch*|git\ reset*|git\ restore*|git\ clean*|git\ stash*|git\ merge*|git\ rebase*|git\ cherry-pick*|git\ apply*|git\ push*|git\ pull*|git\ fetch*|git\ worktree*|git\ rm*|git\ mv*|git\ tag*|git\ branch\ -[dDmM]*)
      decide deny "'$name' is read-only: '$seg' changes the repository." ;;
    npm\ install*|npm\ i\ *|pnpm\ install*|pnpm\ add*|yarn\ add*|yarn\ install*|pip\ install*|go\ get*|go\ mod\ tidy*)
      decide deny "'$name' is read-only: installing dependencies changes files." ;;
  esac
done <<< "$segments"
exit 0
