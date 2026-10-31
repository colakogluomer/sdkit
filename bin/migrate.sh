#!/usr/bin/env bash
# Move a repo set up before 1.0 (project directory .claude, .codex or .agentkit, settings in project.env) into .sdkit/.
# Usage: migrate.sh [--apply] [target-dir]        (reached as: sdkit upgrade --migrate [--apply])
#   Default is a dry run: it lists every move and changes nothing. --apply makes a backup first (.git/sdkit-migrate-<time>.tgz), then:
#   1. moves what the kit owns into .sdkit/ (git mv for tracked files): project.md, project.env -> sdkit.env (shared; its personal settings go to sdkit.local.env), rules/, known-pitfalls.md, adr/,
#      verify.d/, roles.d/, golangci.yml, attestations/, knowledge/ -> memory/, work/, .frozen, .verify-cache/, .sdd/
#   2. removes the kit's generated copies from the old directory (scripts/, hooks/, roles/, tiers.env, and what the manifest lists)
#   3. takes the kit's plugin and hook entries out of .claude/settings.json (they are written to settings.local.json now)
#   4. runs init for the detected hosts, which builds the rest of .sdkit/ (.gitignore, missing settings, host files)
#   Anything else in the old directory is the project's own (skills, commands, agents, .claude/memory, CLAUDE.md ...) and stays where it is.
set -eu
. "$(dirname "$0")/lib.sh"
APPLY=0; TARGET="$PWD"
for arg in "$@"; do case "$arg" in --apply) APPLY=1 ;; -*) say "unknown option $arg"; exit 2 ;; *) TARGET="$(cd "$arg" && pwd)" ;; esac; done

OLD="$(resolve_kit_dir "$TARGET")"
[ -n "$OLD" ] || { say "no sdkit setup found in $TARGET (run sdkit init)"; exit 1; }
[ "$OLD" != .sdkit ] || { say "already on .sdkit/: nothing to migrate"; exit 0; }
ENV_OLD="$(resolve_kit_env "$TARGET" "$OLD")"
[ -e "$TARGET/.sdkit/$ENV_OLD" ] || [ ! -e "$TARGET/.sdkit/sdkit.env" ] || { say ".sdkit/sdkit.env already exists next to the old $OLD/: resolve that by hand first"; exit 1; }
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { say "$TARGET is not a git repository"; exit 1; }
HOSTS="$(detect_hosts "$TARGET")"; MODE="$(detect_mode "$TARGET")"
STACK="$(SDKIT_ENV_QUIET=1; sdkit_env_load_file "$TARGET/$OLD/$ENV_OLD"; echo "${STACK:-$SDKIT_DEFAULT_STACK}")"

say "migrate: $TARGET  $OLD/ ($ENV_OLD) -> .sdkit/   [$([ "$APPLY" = 1 ] && echo apply || echo dry run)]"
tracked() { git -C "$TARGET" ls-files --error-unmatch -- "$1" >/dev/null 2>&1 || [ -n "$(git -C "$TARGET" ls-files -- "$1" | head -1)" ]; }
mv_one() {   # mv_one <old-rel> <new-rel>
  [ -e "$TARGET/$1" ] || return 0
  say "  move   $1 -> $2"
  [ "$APPLY" = 1 ] || return 0
  mkdir -p "$(dirname "$TARGET/$2")"
  if tracked "$1"; then git -C "$TARGET" mv "$1" "$2"; else mv "$TARGET/$1" "$TARGET/$2"; fi
}

if [ "$APPLY" = 1 ]; then
  bk="$(git -C "$TARGET" rev-parse --git-path "sdkit-migrate-$(date +%Y%m%d-%H%M%S).tgz")"; case "$bk" in /*) ;; *) bk="$TARGET/$bk" ;; esac
  ( cd "$TARGET" && tar -czf "$bk" "$OLD" $([ -f .claude/settings.json ] && echo .claude/settings.json) 2>/dev/null ) && say "  backup $bk"
fi

mv_one "$OLD/$ENV_OLD" ".sdkit/sdkit.env"
for f in project.md known-pitfalls.md golangci.yml rules adr verify.d roles.d attestations .frozen .verify-cache .sdd work; do mv_one "$OLD/$f" ".sdkit/$f"; done
mv_one "$OLD/knowledge" ".sdkit/memory"

# the kit's generated copies: listed in the manifest, plus the directories that only held them
gen=()
if [ -f "$TARGET/$OLD/.scaffold-manifest" ]; then
  while IFS="$(printf '\t')" read -r dest _; do
    case "$dest" in "$OLD"/*) [ -e "$TARGET/$dest" ] && gen+=("$dest") ;; esac
  done < "$TARGET/$OLD/.scaffold-manifest"
fi
for f in tiers.env .scaffold-manifest .scaffold-shared .scaffold-version; do [ -e "$TARGET/$OLD/$f" ] && gen+=("$OLD/$f"); done
if [ "${#gen[@]}" -gt 0 ]; then
  say "  remove ${#gen[@]} generated kit file(s) from $OLD/ (init rebuilds them in .sdkit/)"
  if [ "$APPLY" = 1 ]; then
    for f in "${gen[@]}"; do if tracked "$f"; then git -C "$TARGET" rm -q -f -- "$f"; else rm -f "$TARGET/$f"; fi; done
    for d in scripts hooks roles; do [ -d "$TARGET/$OLD/$d" ] && rmdir "$TARGET/$OLD/$d" 2>/dev/null || true; done
  fi
fi

# kit entries in the project's shared Claude settings: the plugin keys and the hook commands
S="$TARGET/.claude/settings.json"
if [ -f "$S" ] && jq -e '(.enabledPlugins["spec-driven-kit@spec-driven-kit"] // .extraKnownMarketplaces["spec-driven-kit"] // false) or ([.. | .command? // empty | select(test("/hooks/(guard|post-edit|stop-verify|record-verdict|usage-log|result-size|session-context|check-tools|check-contract|frozen-tests)"))] | length > 0)' "$S" >/dev/null 2>&1; then
  say "  edit   .claude/settings.json: remove the kit's plugin keys and hook entries (the rest stays)"
  if [ "$APPLY" = 1 ]; then
    tmp="$(mktemp)"
    jq 'del(.enabledPlugins["spec-driven-kit@spec-driven-kit"], .extraKnownMarketplaces["spec-driven-kit"])
        | (if (.enabledPlugins // {}) == {} then del(.enabledPlugins) else . end)
        | (if (.extraKnownMarketplaces // {}) == {} then del(.extraKnownMarketplaces) else . end)
        | if .hooks then .hooks |= (with_entries(.value |= (map(.hooks |= map(select((.command // "") | test("/hooks/(guard|post-edit|stop-verify|record-verdict|usage-log|result-size|session-context|check-tools|check-contract|frozen-tests)") | not)) | select((.hooks // []) | length > 0)))) | with_entries(select(.value | length > 0))) | (if .hooks == {} then del(.hooks) else . end) else . end' "$S" > "$tmp" && mv "$tmp" "$S"
  fi
fi

if [ "$APPLY" = 0 ]; then
  say ""; say "dry run only. Re-run with --apply to do it (a backup is made first), then commit .sdkit/ and the deletions."
  exit 0
fi
say ""; say "building the new layout (hosts: $HOSTS, stack: $STACK)"
KIT_DIR="" "$SCAFFOLD_ROOT/bin/init.sh" --host "$HOSTS" --mode "$MODE" --stack "$STACK" --dir .sdkit "$TARGET" | grep -E '^(  (wrote|added|merge|append|update|FAIL)|done)' || true
say ""; say "migrated. Review with git status, then commit. 'sdkit doctor' checks the result."
