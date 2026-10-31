#!/usr/bin/env bash
# Verifies only what changed relative to the diff base (committed + staged + unstaged + untracked).
# Usage: verify.sh [--fast] [--since-head] [--no-cache]   (see scripts/verify-core.sh)
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
# copy mode: the core sits next to this script; plugin mode: in the kit's scripts/ directory
for _c in "$ENGINE_DIR/verify-core.sh" "$ENGINE_DIR/../../../scripts/verify-core.sh"; do [ -f "$_c" ] && { . "$_c"; break; }; done
type verify_main >/dev/null 2>&1 || { echo "verify-core.sh not found next to $0 or in the kit's scripts/" >&2; exit 1; }
. "$ENGINE_DIR/steps.sh"
verify_main "$@"
