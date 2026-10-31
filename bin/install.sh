#!/usr/bin/env bash
# Register this kit checkout on the machine, so the git-hook shims (.githooks/pre-commit, pre-push) find it in repos that
# do not carry their own copy of the scripts. Run once per machine, per kit checkout.
# Usage: install.sh [--status | --uninstall]
#   writes  ${XDG_CONFIG_HOME:-~/.config}/spec-driven-kit/home   (the absolute path of this checkout)
# SPEC_KIT_HOME in the environment overrides the registered path.
set -eu
. "$(dirname "$0")/lib.sh"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/spec-driven-kit"
home_file="$cfg/home"

case "${1:-}" in
  --status)
    if [ -f "$home_file" ]; then
      reg="$(cat "$home_file")"
      say "registered kit: $reg"
      [ -x "$reg/scripts/guard.sh" ] && say "  ok    scripts/guard.sh found" || { say "  FAIL  $reg/scripts/guard.sh missing (moved or deleted?). Re-run install.sh"; exit 1; }
      [ "$reg" = "$SCAFFOLD_ROOT" ] || say "  note  this checkout ($SCAFFOLD_ROOT) is not the registered one"
    else
      say "no kit registered on this machine. Run: $SCAFFOLD_ROOT/bin/install.sh"; exit 1
    fi ;;
  --uninstall) rm -f "$home_file"; say "unregistered (removed $home_file)" ;;
  "")
    command -v jq >/dev/null || { say "jq is required (brew install jq)"; exit 1; }
    command -v git >/dev/null || { say "git is required"; exit 1; }
    mkdir -p "$cfg"
    printf '%s\n' "$SCAFFOLD_ROOT" > "$home_file"
    say "registered spec-driven-kit $SCAFFOLD_VERSION at $SCAFFOLD_ROOT"
    say "  git hooks in any repo with .githooks/ now find the kit (git config core.hooksPath .githooks, once per clone)" ;;
  *) say "usage: install.sh [--status | --uninstall]"; exit 2 ;;
esac
