#!/usr/bin/env bash
# PreToolUse(Edit|Write): code may only change in the phase that allows it (the rule lives in scripts/sdd.sh gate).
# SDD_MODE (sdkit.env, default strict): strict = deny, guided = ask, off = disabled.
. "$(dirname "$0")/lib.sh"
path="$(jget .tool_input.file_path)"
[ -z "$path" ] && exit 0
sdd="$(kit_cmd "" scripts/sdd.sh)"
mode="$("$sdd" mode)"
[ "$mode" = off ] && exit 0
reason="$("$sdd" gate edit "$path")" && exit 0
[ "$mode" = strict ] && decide deny "$reason" || decide ask "$reason"
