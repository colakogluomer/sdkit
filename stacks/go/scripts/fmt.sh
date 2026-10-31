#!/usr/bin/env bash
# format one Go file; never fails
case "${1:-}" in *.go) [ -f "$1" ] && command -v gofmt >/dev/null 2>&1 && gofmt -w "$1" ;; esac
exit 0
