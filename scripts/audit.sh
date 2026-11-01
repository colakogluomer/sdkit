#!/usr/bin/env bash
# Append-only, hash-chained audit trail (F19): who/what crossed a boundary. Metadata only: type, role, host, byte counts, ids, reason codes; never prompts,
# answers, file contents or secrets (values are redacted and long values refused). The chain makes edits and deletions in the middle detectable; it
# cannot prevent a person with write access from truncating the tail (copy the file elsewhere for that).
#   audit.sh log <type> [key=value ...]     types: egress adapter.exec budget.override policy.fail  (any [a-z.]+ is accepted)
#   audit.sh show [--type T] [-n N]         the last N entries (default 20)
#   audit.sh verify                         recompute the chain; exit 1 and name the first broken line
#   audit.sh policy                         static checks of the enforcement the kit ships (see below); exit 1 on a violation
# File: <project-dir>/audit.jsonl (personal; gitignored via sdkit.local patterns is NOT assumed: keep it out of commits yourself).
# policy checks: read-only roles in agents/ list no Edit/Write/NotebookEdit tool; hooks.json wires guard-secrets, guard-readonly, guard-git, guard-prod
# and guard-protected; no adapter script (adapters.d/*.sh) is group/world-writable; every adapter validates; no secret-shaped string in core/ or adapters.d/.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; top="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$here/env.sh" 2>/dev/null; SDKIT_ENV_QUIET=1 sdkit_env_load "$top" 2>/dev/null; command -v jq >/dev/null || { echo "audit.sh needs jq" >&2; exit 2; }
F="$top/$KIT_DIR/audit.jsonl"; cmd="${1:-}"; shift 2>/dev/null || true
hash() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
case "$cmd" in
  log)
    type="${1:-}"; shift 2>/dev/null || true; case "$type" in ''|*[!a-z.]*) echo "audit: type must match [a-z.]+" >&2; exit 2 ;; esac
    fields='{}'; for kv in "$@"; do k="${kv%%=*}"; v="${kv#*=}"; case "$k" in ''|*[!a-z_]*) echo "audit: bad key '$k'" >&2; exit 2 ;; esac
      [ "${#v}" -le 120 ] || { echo "audit: value of $k is longer than 120 characters; the trail holds metadata, not content" >&2; exit 2; }
      v="$(printf '%s' "$v" | "$here/redact.sh")"; fields="$(jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}' <<< "$fields")"; done
    mkdir -p "$(dirname "$F")"; . "$here/env.sh" 2>/dev/null; sdkit_lock "$F"; trap 'sdkit_unlock "$F"' EXIT
    prev=0000; [ -s "$F" ] && prev="$(tail -1 "$F" | jq -r .h)"
    body="$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg t "$type" --arg p "$prev" --argjson f "$fields" '{ts:$ts, type:$t, prev:$p} + $f')"
    printf '%s\n' "$(jq -c --arg h "$(hash "$body")" '. + {h:$h}' <<< "$body")" >> "$F" ;;
  show) t=""; n=20; while [ $# -gt 0 ]; do case "$1" in --type) t="$2"; shift ;; -n) n="$2"; shift ;; esac; shift; done
    [ -f "$F" ] || { echo "audit: no entries"; exit 0; }; jq -c --arg t "$t" 'select($t == "" or .type == $t)' "$F" | tail -n "$n" ;;
  verify) [ -f "$F" ] || { echo "audit: no entries (ok)"; exit 0; }
    prev=0000; i=0; while IFS= read -r line; do i=$((i + 1))
      h="$(jq -r .h <<< "$line" 2>/dev/null)"; body="$(jq -c 'del(.h)' <<< "$line" 2>/dev/null)"
      [ "$(jq -r .prev <<< "$line" 2>/dev/null)" = "$prev" ] && [ "$(hash "$body")" = "$h" ] || { echo "audit: chain broken at line $i"; exit 1; }
      prev="$h"; done < "$F"; echo "audit: chain ok ($i entries)" ;;
  policy) bad=0; fail() { echo "FAIL: $*"; bad=1; }
    for f in "$here/../agents"/*.md; do [ -f "$f" ] || continue; r="$(basename "$f" .md)"; r="${r%-deep}"
      src="$here/../core/roles/$r.md"; [ -f "$src" ] || continue
      if [ "$(sed -n 's/^access:[[:space:]]*//p' "$src" | head -1)" = read-only ]; then
        tl="$(sed -n 's/^tools:[[:space:]]*//p' "$f" | head -1)"; case ",$tl," in *Edit*|*Write*|*NotebookEdit*) fail "read-only role $r lists a write tool in agents/$(basename "$f"): $tl" ;; esac; fi; done
    for h in guard-secrets guard-readonly guard-git guard-prod guard-protected; do grep -q "$h.sh" "$here/../hooks/hooks.json" || fail "hooks.json does not wire $h.sh"; done
    for a in "$here/../adapters.d"/*.sh; do [ -f "$a" ] || continue; [ -z "$(find "$a" -perm -020 -o -perm -002 2>/dev/null)" ] || fail "$a is group/world-writable"
      "$here/adapter.sh" validate "ext:$(basename "$a" .sh)" >/dev/null 2>&1 || fail "adapter $(basename "$a") does not validate"; done
    hits="$(grep -rEl -- '-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{24,}' "$here/../core" "$here/../adapters.d" 2>/dev/null | head -3)"
    [ -z "$hits" ] || fail "secret-shaped string in: $hits"
    [ "$bad" = 0 ] && echo "audit policy: ok"; exit "$bad" ;;
  *) echo "usage: audit.sh log|show|verify|policy" >&2; exit 2 ;;
esac
