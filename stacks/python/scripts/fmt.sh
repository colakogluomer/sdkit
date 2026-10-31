#!/usr/bin/env bash
# format one Python file; never fails
case "${1:-}" in
  *.py) [ -f "$1" ] || exit 0
        if command -v ruff >/dev/null 2>&1; then ruff format -q "$1"
        elif command -v black >/dev/null 2>&1; then black -q "$1"; fi ;;
esac
exit 0
