#!/usr/bin/env bash
# format one JS/TS file with the project's local prettier; never fails
case "${1:-}" in
  *.ts|*.tsx|*.js|*.jsx)
    [ -f "$1" ] || exit 0
    dir="$(dirname "$1")"
    while :; do
      [ -x "$dir/node_modules/.bin/prettier" ] && { "$dir/node_modules/.bin/prettier" --write "$1" >/dev/null 2>&1; break; }
      [ "$dir" = "." ] || [ "$dir" = "/" ] && break
      dir="$(dirname "$dir")"
    done ;;
esac
exit 0
