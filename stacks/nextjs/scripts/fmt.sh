#!/usr/bin/env bash
# format one JS/TS/CSS/JSON file with the project's local prettier; never fails
case "${1:-}" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.md)
    d="$(dirname "$1")"
    while :; do
      if [ -x "$d/node_modules/.bin/prettier" ]; then "$d/node_modules/.bin/prettier" --write "$1" >/dev/null 2>&1; break; fi
      [ "$d" = "." ] || [ "$d" = "/" ] && break
      d="$(dirname "$d")"
    done ;;
esac
exit 0
