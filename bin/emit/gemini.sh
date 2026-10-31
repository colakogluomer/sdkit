# Gemini CLI emitter: adapters/gemini/agents/<role>.md (project: .gemini/agents/). Sourced by build-adapters.sh.
# `tools` lists only what the role may use; read-only roles keep shell for git/verify, narrowed by hooks/guard-readonly.sh.
GEMINI_DIRS="adapters/gemini"
emit_gemini_begin() { mkdir -p "$OUT/adapters/gemini/agents"; }
emit_gemini_role() {
  local model tools t
  eval "model=\$GEMINI_MODEL_$T"
  tools="$GEMINI_TOOLS_READ"; [ "$RO" = 1 ] || tools="$tools, $GEMINI_TOOLS_WRITE"
  { printf -- '---\nname: %s\ndescription: "%s"\ntools:\n' "$NAME" "$(printf '%s' "$DESC" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    for t in $(printf '%s' "$tools" | tr -d ' ' | tr ',' ' '); do printf '  - %s\n' "$t"; done
    [ -z "$model" ] || printf 'model: %s\n' "$model"
    printf -- '---\n<!-- %s -->\n%s\n' "$NOTE" "$PREAMBLE"
    cat "$BODYFILE"; } > "$OUT/adapters/gemini/agents/$NAME.md"
}
