#!/usr/bin/env bash
# format one Java or Kotlin file; never fails
case "${1:-}" in
  *.java) [ -f "$1" ] && command -v google-java-format >/dev/null 2>&1 && google-java-format --replace "$1" ;;
  *.kt|*.kts) [ -f "$1" ] && command -v ktlint >/dev/null 2>&1 && ktlint -F "$1" >/dev/null 2>&1 ;;
esac
exit 0
