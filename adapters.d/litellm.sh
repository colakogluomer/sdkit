#!/usr/bin/env bash
# Optional external adapter (F13): any OpenAI-compatible chat endpoint, e.g. a LiteLLM proxy (POST <base>/chat/completions). Off unless configured.
# It is a TEXT-ONLY adapter: no tools, no file access, so it refuses roles that write or that must inspect the tree themselves (verifier, reviewer,
# security-auditor, any writing role). Claude subscription traffic does not go through it. Contract: docs/design-adapters.md.
# Settings (sdkit.local.env / environment; the key is never read from a file in the repo):
#   LITELLM_BASE_URL       e.g. http://localhost:4000/v1                       (required)
#   LITELLM_MODEL          default model id the endpoint knows                 (required unless --model is passed)
#   LITELLM_API_KEY_ENV    NAME of the environment variable holding the key (default LITELLM_API_KEY); empty key = no Authorization header
#   LITELLM_EGRESS=allow   REQUIRED: the prompt (role text + handoff, may quote repo content) leaves this machine. No value, no request.
#   LITELLM_ALLOW_HOSTS    space-separated host[:port] allow-list for the base URL (default: localhost and 127.0.0.1 only)
# FusionCLI: its command surface could not be verified from here, so there is deliberately no FusionCLI adapter; add one only against its real --help.
set -u
verb="${1:-}"; shift 2>/dev/null || true
case "$verb" in
  capabilities) echo '{"noninteractive":"declared","tool_use":"none","model_selection":"declared","usage_reporting":"declared","structured_output":"none","cancellation":"none","timeout":"kit","cost_reporting":"none"}'; exit 0 ;;
  execute) ;;
  *) exit 3 ;;
esac
role=""; model=""; ro=1; pf=""
while [ $# -gt 0 ]; do case "$1" in --role) role="$2"; shift ;; --model) model="$2"; shift ;; --ro) ro="$2"; shift ;; --prompt-file) pf="$2"; shift ;; --cwd|--tier) shift ;; esac; shift; done
die() { local m="litellm adapter: $1"; [ -n "${key:-}" ] && m="${m//"$key"/***}"; m="$(printf '%s' "$m" | "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/redact.sh")"; echo "$m" >&2; exit "${2:-4}"; }
case "${role%-deep}" in verifier|reviewer|security-auditor) die "refuses $role: a text-only adapter cannot inspect the tree itself, and an independent verdict must not rest on pasted content" ;; esac
[ "$ro" = 1 ] || die "refuses a role that writes files (text-only adapter)"
[ "${LITELLM_EGRESS:-}" = allow ] || die "LITELLM_EGRESS=allow is not set: the prompt would leave this machine, so nothing was sent"
base="${LITELLM_BASE_URL:-}"; [ -n "$base" ] || die "LITELLM_BASE_URL is not set"
model="${model:-${LITELLM_MODEL:-}}"; [ -n "$model" ] || die "no model (--model or LITELLM_MODEL)"
hp="${base#*://}"; hp="${hp%%/*}"; ok=0
for a in ${LITELLM_ALLOW_HOSTS:-localhost:4000 127.0.0.1:4000 localhost 127.0.0.1}; do [ "$hp" = "$a" ] || [ "${hp%%:*}" = "$a" ] && ok=1; done
[ "$ok" = 1 ] || die "host '$hp' is not in LITELLM_ALLOW_HOSTS"
[ -f "$pf" ] || die "no prompt file" 2
# the audit record comes first: no record, no egress (metadata only: host, model, role, bytes; never the prompt)
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/audit.sh" log egress adapter=litellm host="$hp" model="$model" role="$role" bytes="$(wc -c < "$pf" | tr -d ' ')" >/dev/null 2>&1 || die "could not write the audit record, so nothing was sent"
keyvar="${LITELLM_API_KEY_ENV:-LITELLM_API_KEY}"; key="${!keyvar:-}"
body="$(jq -nc --arg m "$model" --rawfile p "$pf" '{model: $m, messages: [{role: "user", content: $p}]}')" || die "cannot build the request" 2
# the key goes to curl on stdin (-K -), never on the command line where `ps` would show it
resp="$( { [ -n "$key" ] && printf 'header = "Authorization: Bearer %s"\n' "$key"; printf 'header = "Content-Type: application/json"\n'; } | curl -sS --max-time "${LITELLM_TIMEOUT_S:-300}" -K - -d "$body" "${base%/}/chat/completions" 2>&1)" || die "request failed: $(printf '%s' "$resp" | head -c 300)" 5
if jq -e '.error' <<< "$resp" >/dev/null 2>&1; then die "provider error: $(jq -r '.error.message // .error | tostring' <<< "$resp" | head -c 300)" 5; fi
jq -e '.choices[0].message.content' <<< "$resp" >/dev/null 2>&1 || die "unexpected response shape (no choices[0].message.content)" 5
jq -c '{result: .choices[0].message.content} + (if (.usage.prompt_tokens != null and .usage.completion_tokens != null) then {usage: {input_tokens: .usage.prompt_tokens, output_tokens: .usage.completion_tokens}} else {} end)' <<< "$resp"
