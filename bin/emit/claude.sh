# Claude Code emitter: agents/<role>.md. Sourced by build-adapters.sh.
CLAUDE_DIRS="agents"
emit_claude_begin() { mkdir -p "$OUT/agents"; }
emit_claude_role() {
  local tools="Read, Grep, Glob, Bash" cmodel
  [ "$RO" = 1 ] || tools="$tools, Edit, Write"
  eval "cmodel=\$CLAUDE_MODEL_$T"
  { printf -- '---\nname: %s\ndescription: %s\ntools: %s\nmodel: %s\n---\n<!-- %s -->\n%s\n' "$NAME" "$DESC" "$tools" "$cmodel" "$NOTE" "$PREAMBLE"
    cat "$BODYFILE"; } > "$OUT/agents/$NAME.md"
}
