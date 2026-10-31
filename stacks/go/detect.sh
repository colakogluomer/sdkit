#!/usr/bin/env bash
# exit 0 when $1 contains a Go module
[ -n "$(find "${1:-.}" -maxdepth 3 -name go.mod -not -path '*/node_modules/*' 2>/dev/null | head -1)" ]
