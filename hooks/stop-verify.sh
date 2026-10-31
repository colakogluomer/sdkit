#!/usr/bin/env bash
# Stop: block "done" while uncommitted Go changes fail vet/build.
. "$(dirname "$0")/lib.sh"
# a second Stop caused by our own block must not loop forever
[ "$(jget .stop_hook_active)" = "true" ] && exit 0
verify_cmd="$(kit_cmd "${VERIFY_CMD:-}" "stacks/$STACK/scripts/verify.sh")"
[ -x "$verify_cmd" ] || exit 0

output="$(cd "$PROJECT_DIR" && "$verify_cmd" --fast --since-head 2>&1)" && exit 0
jq -n --arg out "$(printf '%s' "$output" | tail -30)" \
  '{decision:"block",reason:("verify failed, fix before finishing:\n" + $out)}'
exit 0
