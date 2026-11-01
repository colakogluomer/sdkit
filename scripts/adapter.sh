#!/usr/bin/env bash
# The execution-adapter contract (F12), one entry point for the five contract verbs. Built-in hosts (claude codex opencode cursor gemini) keep
# working exactly as before through run-role.sh; this script only reports what they support, honestly. An external adapter is an executable
# <project-dir>/adapters.d/<name>.sh (or the kit's adapters.d/) that run-role.sh calls as --host ext:<name>. Contract: docs/design-adapters.md.
#   adapter.sh capabilities <host|ext:name> [--json]   the 8 capability keys (adapters.json for built-ins; the adapter's own `capabilities` output otherwise)
#   adapter.sh usage <host|ext:name>                    what usage the adapter reports: actual | none | unsupported  (never a zero)
#   adapter.sh cancel <host|ext:name> [id]              exit 3 = unsupported (built-ins: timeout only, via run-role); an ext adapter may implement `cancel`
#   adapter.sh status <host|ext:name> [id]              exit 3 = unsupported; an ext adapter may implement `status`; the kit's own record is `sdd.sh evidence`
#   adapter.sh validate <ext:name>                      the adapter answers `capabilities` with exactly the required keys and legal values
#   (execute = run-role.sh --host <host>; evidence = parse-verdict.sh --record, run by run-role.sh: an adapter never records its own verdict)
# Exit: 0 ok, 1 invalid adapter, 2 usage / unknown, 3 unsupported capability.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; top="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
KIT_DIR=.sdkit; [ -f "$here/env.sh" ] && { . "$here/env.sh" 2>/dev/null; SDKIT_ENV_QUIET=1 sdkit_env_load "$top" 2>/dev/null; }
verb="${1:-}"; host="${2:-}"; shift 2 2>/dev/null || true
KEYS='["noninteractive","tool_use","model_selection","usage_reporting","structured_output","cancellation","timeout","cost_reporting"]'
VALS='["help-verified","declared","estimated","kit","none"]'
find_ext() { local n="${1#ext:}" c; case "$n" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  for c in "$top/$KIT_DIR/adapters.d/$n.sh" "$here/../adapters.d/$n.sh"; do [ -x "$c" ] && { echo "$c"; return 0; }; done; return 1; }
builtin() { jq -e --arg h "$1" 'has($h) and ($h | startswith("_") | not)' "$here/../core/adapters.json" >/dev/null 2>&1; }
caps_of() {  # <host>: capabilities JSON on stdout
  case "$1" in
    ext:*) local f; f="$(find_ext "$1")" || { echo "adapter: no executable adapter '${1#ext:}'" >&2; return 2; }; "$f" capabilities 2>/dev/null ;;
    *) builtin "$1" || { echo "adapter: unknown host '$1'" >&2; return 2; }; jq --arg h "$1" '.[$h].caps' "$here/../core/adapters.json" ;;
  esac
}
valid_caps() { jq -e --argjson k "$KEYS" --argjson v "$VALS" 'type == "object" and (keys | sort) == ($k | sort) and ([.[]] | all(. as $x | $v | index($x) != null))' >/dev/null 2>&1; }
case "$verb" in
  capabilities) c="$(caps_of "$host")" || exit 2; [ -n "$c" ] || exit 1
    if [ "${1:-}" = --json ]; then echo "$c" | jq .; else echo "$c" | jq -r 'to_entries[] | "\(.key)=\(.value)"'; fi ;;
  usage) c="$(caps_of "$host")" || exit 2; u="$(echo "$c" | jq -r '.usage_reporting // "none"')"
    case "$u" in none) echo "none: $host reports no token usage; its runs are logged as unmeasured, never as zero" ;; *) echo "$u: $host reports tokens (cache and cost are separate capabilities)" ;; esac ;;
  cancel|status) case "$host" in
      ext:*) f="$(find_ext "$host")" || exit 2; "$f" "$verb" "$@" 2>/dev/null; rc=$?; [ "$rc" = 0 ] || { echo "unsupported: ${host#ext:} does not implement $verb"; exit 3; } ;;
      *) builtin "$host" || exit 2; echo "unsupported: $host has no $verb (run-role.sh enforces a timeout where a timeout command exists; the kit's record is sdd.sh evidence)"; exit 3 ;;
    esac ;;
  validate) f="$(find_ext "$host")" || { echo "adapter: no executable adapter '${host#ext:}'" >&2; exit 2; }
    "$f" capabilities 2>/dev/null | valid_caps || { echo "invalid: capabilities must be a JSON object with exactly the 8 keys and values in help-verified|declared|estimated|kit|none"; exit 1; }
    echo "valid: ${host#ext:}" ;;
  *) echo "usage: adapter.sh capabilities|usage|cancel|status|validate <host|ext:name> ..." >&2; exit 2 ;;
esac
