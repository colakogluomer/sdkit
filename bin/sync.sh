#!/usr/bin/env bash
# Pull scaffold updates into a project without clobbering local edits.
# Usage: sync.sh [--force] [--check] [target-dir]
#   --check  change nothing; exit 1 when a managed copy is missing or differs from this kit (use it in CI to catch drift)
set -eu
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/shared.sh"

FORCE=0
CHECK=0
PENDING=0
TARGET="$PWD"
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --check) CHECK=1 ;;
    *) TARGET="$(cd "$arg" && pwd)" ;;
  esac
done

KIT_DIR="$(resolve_kit_dir "$TARGET")"
[ -n "$KIT_DIR" ] || { say "no sdkit.env found in .sdkit/ (or project.env in a legacy .agentkit/, .claude/, .codex/); run init.sh first"; exit 1; }
export KIT_ENV="$(resolve_kit_env "$TARGET" "$KIT_DIR")"
manifest="$TARGET/$KIT_DIR/.scaffold-manifest"
[ -f "$manifest" ] || { say "no manifest at $manifest; run init.sh first"; exit 1; }
say "scaffold $(cat "$TARGET/$KIT_DIR/.scaffold-version") -> $SCAFFOLD_VERSION"

[ "$CHECK" = 1 ] && manifest_new=/dev/null || manifest_new="$manifest.new"
: > "$manifest_new"
while IFS="$(printf '\t')" read -r dest src installed_sha; do
  [ -f "$SCAFFOLD_ROOT/$src" ] || { say "  gone   $dest (removed upstream; left in place)"; continue; }
  rendered="$(mktemp)"; render_managed "$SCAFFOLD_ROOT/$src" "$dest" > "$rendered"
  if [ "$CHECK" = 1 ]; then
    if [ ! -f "$TARGET/$dest" ]; then say "  missing $dest"; PENDING=1
    elif ! cmp -s "$rendered" "$TARGET/$dest"; then say "  drift   $dest differs from kit $SCAFFOLD_VERSION"; PENDING=1; fi
    rm -f "$rendered"; continue
  fi
  if [ ! -f "$TARGET/$dest" ]; then
    mkdir -p "$(dirname "$TARGET/$dest")"; cp -p "$SCAFFOLD_ROOT/$src" "$TARGET/$dest"; cat "$rendered" > "$TARGET/$dest"
    say "  added  $dest"
  elif cmp -s "$rendered" "$TARGET/$dest"; then
    :
  elif [ "$(sha "$TARGET/$dest")" = "$installed_sha" ] || [ "$FORCE" = 1 ]; then
    cp -p "$SCAFFOLD_ROOT/$src" "$TARGET/$dest"; cat "$rendered" > "$TARGET/$dest"
    say "  update $dest"
  else
    say "  CONFLICT $dest edited locally and changed upstream; diff below, rerun with --force to take upstream"
    diff -u "$TARGET/$dest" "$rendered" | head -40 || true
    printf '%s\t%s\t%s\n' "$dest" "$src" "$installed_sha" >> "$manifest_new"
    rm -f "$rendered"; continue
  fi
  rm -f "$rendered"
  record_managed "$dest" "$src"
done < "$manifest"

say "shared files (kit part only; yours is never touched)"
if [ "$CHECK" = 1 ]; then refresh_shared check || PENDING=1; else refresh_shared write || true; fi
if [ "$CHECK" = 1 ]; then
  [ "$PENDING" = 0 ] && say "in sync with kit $SCAFFOLD_VERSION" || { say "drift found: run sync.sh (or upgrade.sh) and commit the result"; exit 1; }
  exit 0
fi
mv "$manifest.new" "$manifest"
printf '%s\n' "$SCAFFOLD_VERSION" > "$TARGET/$KIT_DIR/.scaffold-version"
say "sync done"
