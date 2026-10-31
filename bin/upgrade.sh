#!/usr/bin/env bash
# Bring a project that already uses the kit up to this kit version, without touching what the project owns.
# Usage: upgrade.sh [--migrate [--apply]] [target-dir]
#   --migrate  move a repo set up before 1.0 (.claude/.codex/.agentkit + project.env) into .sdkit/ (dry run unless --apply; see migrate.sh)
# It detects the project's hosts/mode/stack, adds files that are new in this kit version, adds missing lines to the
# project .gitignore, runs sync.sh for copy-mode installs, prints the manual steps for the versions you skipped, and runs doctor.
# It never overwrites project.md, sdkit.env (it only appends settings that are new), rules, known-pitfalls, settings.json or any other file the project edited.
set -eu
. "$(dirname "$0")/lib.sh"
MIGRATE=0; MIGRATE_ARGS=(); TARGET="$PWD"
for arg in "$@"; do case "$arg" in --migrate) MIGRATE=1 ;; --apply) MIGRATE_ARGS+=(--apply) ;; -*) say "unknown option $arg"; exit 2 ;; *) TARGET="$(cd "$arg" && pwd)" ;; esac; done
[ "$MIGRATE" = 0 ] || exec "$(dirname "$0")/migrate.sh" ${MIGRATE_ARGS[@]+"${MIGRATE_ARGS[@]}"} "$TARGET"

KIT_DIR="$(resolve_kit_dir "$TARGET")"
[ -n "$KIT_DIR" ] || { say "no sdkit.env in .sdkit/ (or project.env in a legacy .agentkit/, .claude/, .codex/): this repo is not set up (run init.sh)"; exit 1; }
ENV_FILE="$(resolve_kit_env "$TARGET" "$KIT_DIR")"; export KIT_ENV="$ENV_FILE"
FROM="$(cat "$TARGET/$KIT_DIR/.scaffold-version" 2>/dev/null || echo unknown)"
say "upgrade: $TARGET (project dir $KIT_DIR): kit $FROM -> $SCAFFOLD_VERSION"

HOSTS="$(detect_hosts "$TARGET")"; MODE="$(detect_mode "$TARGET")"
STACK="$(SDKIT_ENV_QUIET=1; sdkit_env_load_file "$TARGET/$KIT_DIR/$ENV_FILE"; echo "${STACK:-$SDKIT_DEFAULT_STACK}")"
say "detected: host=$HOSTS mode=$MODE stack=$STACK"

say ""; say "1. new files (existing files are kept)"
"$SCAFFOLD_ROOT/bin/init.sh" --host "$HOSTS" --mode "$MODE" --stack "$STACK" --dir "$KIT_DIR" "$TARGET" | grep -E '^  wrote' || say "  nothing new"

say ""; say "2. .gitignore lines"
gi="$TARGET/$KIT_DIR/.gitignore"
if [ -f "$gi" ]; then
  added=0
  while IFS= read -r line; do
    case "$line" in ''|'#'*|'!'*) continue ;; esac
    grep -qxF "$line" "$gi" || { printf '%s\n' "$line" >> "$gi"; say "  added  $line"; added=1; }
  done < "$SCAFFOLD_ROOT/$([ "$KIT_DIR" = .sdkit ] && echo templates/sdkit.gitignore || echo templates/claude.gitignore)"
  [ "$added" = 1 ] || say "  up to date"
fi

say ""; say "3. managed copies (sync.sh)"
"$SCAFFOLD_ROOT/bin/sync.sh" "$TARGET" | tail -n +2

say ""; say "4. what to do by hand"
notes="$SCAFFOLD_ROOT/docs/upgrading.md"
if [ -f "$notes" ]; then
  say "  see $notes (sections for versions after $FROM)"
fi
case "$MODE" in plugin) say "  plugin mode: also refresh the plugin in Claude Code (/plugin, update spec-driven-kit) so the new skills, roles and hooks load." ;; esac

say ""; "$SCAFFOLD_ROOT/bin/doctor.sh" "$TARGET" || true
printf '%s\n' "$SCAFFOLD_VERSION" > "$TARGET/$KIT_DIR/.scaffold-version"
