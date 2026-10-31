# Cursor emitter: adapters/cursor/agents/<role>.md (project: .cursor/agents/). Sourced by build-adapters.sh.
CURSOR_DIRS="adapters/cursor"
emit_cursor_begin() { mkdir -p "$OUT/adapters/cursor/agents"; }
emit_cursor_role() {
  local model ro=false
  eval "model=\$CURSOR_MODEL_$T"; [ -n "$model" ] || model=inherit
  [ "$RO" = 1 ] && ro=true
  { printf -- '---\nname: %s\ndescription: "%s"\nmodel: %s\nreadonly: %s\n---\n<!-- %s -->\n%s\n' \
      "$NAME" "$(printf '%s' "$DESC" | sed 's/\\/\\\\/g; s/"/\\"/g')" "$model" "$ro" "$NOTE" "$PREAMBLE"
    cat "$BODYFILE"; } > "$OUT/adapters/cursor/agents/$NAME.md"
}
