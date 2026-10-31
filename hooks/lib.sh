# Shared helpers for hooks. Source this; do not execute.
# Hooks receive the tool-call JSON on stdin and read project values from <project-dir>/sdkit.env.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
INPUT="$(cat)"

# Where this plugin lives (hooks sit in <plugin>/hooks). Used to find the kit's own scripts.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# project dir (.sdkit, or a pre-1.0 one) and the settings: sdkit.env, then sdkit.local.env, parsed and never executed (scripts/env.sh)
for _env in "$PLUGIN_ROOT/scripts/env.sh" "$PROJECT_DIR"/.sdkit/scripts/env.sh "$PROJECT_DIR"/.agentkit/scripts/env.sh "$PROJECT_DIR"/.claude/scripts/env.sh "$PROJECT_DIR"/.codex/scripts/env.sh; do
  [ -f "$_env" ] && { . "$_env" && sdkit_env_load "$PROJECT_DIR"; break; }   # copy-mode hooks do not sit next to the scripts
done
export KIT_DIR

# kit_cmd <configured value> <plugin-relative default>
# A value set in sdkit.env is a path relative to the project (copy mode); empty means use the plugin's script.
kit_cmd() {
  case "$1" in
    "") echo "$PLUGIN_ROOT/$2" ;;
    /*) echo "$1" ;;
    *) echo "$PROJECT_DIR/$1" ;;
  esac
}

jget() { printf '%s' "$INPUT" | jq -r "$1 // empty"; }

# decide <allow|ask|deny> <reason>: emit a PreToolUse permission decision and exit
decide() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# matches_glob_list <path> <comma-separated globs>: true if basename or path matches any glob
matches_glob_list() {
  local path="$1" globs="$2" glob base
  base="$(basename "$path")"
  IFS=',' read -r -a patterns <<< "$globs"
  for glob in "${patterns[@]}"; do
    [ -z "$glob" ] && continue
    case "$base" in $glob) return 0 ;; esac
    case "$path" in $glob) return 0 ;; esac
  done
  return 1
}
