#!/usr/bin/env bash
# Task-scoped, content-hash-versioned discovery notes (F16): "how does X work" summaries a role wrote once, reusable while the files they were
# about are unchanged. Finer than lookup-cache.sh (which drops everything when HEAD or the diff moves): a note lists the files it covers and stays
# valid exactly while each of those files has the same content (sha256). Any change, or a deleted file, makes it stale and `get` says which.
#   knowledge.sh put <slug> <key> --files "a b c" [--title T]   store the note read from stdin (refuses a body that looks like a secret)
#   knowledge.sh get <slug> <key> [--role R]                    print it when every covered file is unchanged; exit 1 stale/missing (names the changed files)
#   knowledge.sh list <slug>                                    key, covered file count, fresh|stale, title
#   knowledge.sh clear <slug>
# A note is the writer's claim, never evidence: independent roles (verifier, reviewer, security-auditor) are refused (`get --role`, exit 5): they read
# the diff and the code themselves. The printed note starts with an UNTRUSTED line. Files: <project-dir>/work/<slug>/knowledge/<key>.{md,json} (personal, gitignored).
# Exit: 0 ok, 1 miss/stale, 2 usage, 5 role must not use summaries.
set -u
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "knowledge.sh needs a git repository" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || exit 2; sdkit_resolve_dir "$top"
cmd="${1:-}"; slug="${2:-}"; key="${3:-}"; [ $# -ge 2 ] && shift 2 || true; [ "$cmd" = put ] || [ "$cmd" = get ] && { shift 1 2>/dev/null || true; }
files=""; title=""; role=""
while [ $# -gt 0 ]; do case "$1" in --files) files="$2"; shift ;; --title) title="$2"; shift ;; --role) role="$2"; shift ;; esac; shift; done
[ -n "$cmd" ] && [ -n "$slug" ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
dir="$top/$KIT_DIR/work/$slug/knowledge"
case "$key" in *[!A-Za-z0-9_.-]*) echo "knowledge: key may use letters, digits, . _ - only" >&2; exit 2 ;; esac
hashes() { local f; for f in $1; do if [ -f "$top/$f" ]; then printf '%s  %s\n' "$(shasum -a 256 "$top/$f" | cut -d' ' -f1)" "$f"; else printf 'MISSING  %s\n' "$f"; fi; done; }
case "$cmd" in
  put)
    [ -n "$key" ] && [ -n "$files" ] || { echo "usage: knowledge.sh put <slug> <key> --files \"a b\"" >&2; exit 2; }
    body="$(cat)"; [ -n "$body" ] || { echo "knowledge: empty note" >&2; exit 2; }
    printf '%s' "$body" | grep -Eqi '(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{16,}' && { echo "knowledge: the note looks like it holds a secret; not stored" >&2; exit 2; }
    mkdir -p "$dir"; printf '%s\n' "$body" > "$dir/$key.md"
    jq -n --arg t "${title:-$key}" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg h "$(hashes "$files")" '{title:$t, ts:$ts, hashes:($h | split("\n") | map(select(length > 0)))}' > "$dir/$key.json"
    echo "stored $key (covers $(printf '%s\n' $files | wc -l | tr -d ' ') file(s))" ;;
  get)
    case "${role%-deep}" in verifier|reviewer|security-auditor) echo "knowledge: $role is an independent role; it reads the code and the diff itself, never a summary" >&2; exit 5 ;; esac
    [ -f "$dir/$key.json" ] || { echo "miss: no note '$key'" >&2; exit 1; }
    stale=""; while IFS= read -r line; do h="${line%%  *}"; f="${line#*  }"
      now="$(hashes "$f")"; [ "${now%%  *}" = "$h" ] || stale="$stale $f"; done < <(jq -r '.hashes[]' "$dir/$key.json")
    [ -z "$stale" ] || { echo "stale: changed or removed since the note was written:$stale" >&2; exit 1; }
    echo "UNTRUSTED SUMMARY (a claim by the role that wrote it, valid only for the file contents it was hashed against; not evidence)"; cat "$dir/$key.md" ;;
  list)
    for j in "$dir"/*.json; do [ -f "$j" ] || continue; k="$(basename "$j" .json)"
      st=fresh; "$0" get "$slug" "$k" >/dev/null 2>&1 || st=stale
      echo "$k $(jq '.hashes | length' "$j") $st $(jq -r .title "$j")"; done ;;
  clear) rm -rf "$dir"; echo "cleared" ;;
  *) echo "usage: knowledge.sh put|get|list|clear <slug> ..." >&2; exit 2 ;;
esac
