#!/usr/bin/env bash
# format one Java file; never fails
case "${1:-}" in *.java) [ -f "$1" ] && command -v google-java-format >/dev/null 2>&1 && google-java-format --replace "$1" ;; esac
exit 0
