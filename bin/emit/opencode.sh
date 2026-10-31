# OpenCode emitter: adapters/opencode/agents/<role>.md (project: .opencode/agents/). Sourced by build-adapters.sh.
# Read-only roles get edit denied and a shell allow-list (last matching rule wins, so "*": deny comes first).
OPENCODE_DIRS="adapters/opencode"
emit_opencode_begin() { mkdir -p "$OUT/adapters/opencode/agents"; }
emit_opencode_role() {
  local model p
  eval "model=\$OPENCODE_MODEL_$T"
  { printf -- '---\ndescription: "%s"\nmode: subagent\n' "$(printf '%s' "$DESC" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    [ -z "$model" ] || printf 'model: %s\n' "$model"
    if [ "$RO" = 1 ]; then
      printf 'permission:\n  edit: deny\n  %s:\n    "*": deny\n' "$OPENCODE_SHELL_KEY"
      local IFS='|'; for p in $READONLY_SHELL_ALLOW; do printf '    "%s": allow\n' "$p"; done
    else
      printf 'permission:\n  edit: allow\n'
    fi
    printf -- '---\n<!-- %s -->\n%s\n' "$NOTE" "$PREAMBLE"
    cat "$BODYFILE"; } > "$OUT/adapters/opencode/agents/$NAME.md"
}
