#!/usr/bin/env bash
# F13 optional OpenAI-compatible/LiteLLM adapter: policy refusals, egress opt-in, secrets, provider errors. A fake curl; no network, no key.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; LL="$ROOT/adapters.d/litellm.sh"; AD="$ROOT/scripts/adapter.sh"
T="$(mktemp -d)"; mkdir -p "$T/proj/.sdkit"; export CLAUDE_PROJECT_DIR="$T/proj"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/bin"; printf 'hello' > "$T/p"
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }
cat > "$T/bin/curl" <<'X'
#!/usr/bin/env bash
echo "ARGS $@" >> "$FAKE_LOG"; [ "$1" = -sS ] && cat >> "$FAKE_LOG"
case "${FAKE_MODE:-ok}" in
  ok) echo '{"choices":[{"message":{"content":"fine"}}],"usage":{"prompt_tokens":5,"completion_tokens":3}}' ;;
  nousage) echo '{"choices":[{"message":{"content":"fine"}}]}' ;;
  err) echo '{"error":{"message":"rate limited, key sk-SECRET123"}}' ;;
  shape) echo '{"weird":1}' ;;
  down) echo "curl: (7) connection refused" >&2; exit 7 ;;
esac
X
chmod +x "$T/bin/curl"; export PATH="$T/bin:$PATH" FAKE_LOG="$T/log"
run() { LITELLM_BASE_URL="${BASE:-http://localhost:4000/v1}" LITELLM_MODEL=m1 LITELLM_EGRESS="${EG-allow}" LITELLM_API_KEY=sk-SECRET123 "$LL" execute --role "${ROLE:-scout}" --ro "${RO:-1}" --prompt-file "$T/p" "$@"; }
eq "capabilities validate through adapter.sh"   "$("$AD" validate ext:litellm | cut -c1-6)" valid:
eq "no tools claimed"                           "$("$LL" capabilities | jq -r .tool_use)" none
out="$(run 2>&1)"; eq "ok: result and measured usage" "$out" '{"result":"fine","usage":{"input_tokens":5,"output_tokens":3}}'
eq "the endpoint is the base URL + /chat/completions" "$(grep -c '^ARGS .*http://localhost:4000/v1/chat/completions' "$T/log")" 1
eq "the key reaches curl on stdin"           "$(grep -c 'Authorization: Bearer sk-SECRET123' "$T/log")" 1
eq "…and never on the command line"          "$(grep '^ARGS' "$T/log" | grep -c 'sk-SECRET123')" 0
FAKE_MODE=nousage run 2>&1 | jq -e 'has("usage") | not' >/dev/null; eq "no usage in the response: none reported (not zero)" "$?" 0
: > "$T/log"
eq "no egress opt-in: refused (4), nothing sent"  "$(EG= run >/dev/null 2>&1; echo $?):$(wc -l < "$T/log" | tr -d ' ')" "4:0"
eq "verifier refused"                           "$(ROLE=verifier run >/dev/null 2>&1; echo $?)" 4
eq "reviewer-deep refused"                      "$(ROLE=reviewer-deep run >/dev/null 2>&1; echo $?)" 4
eq "a writing role refused"                     "$(RO=0 run >/dev/null 2>&1; echo $?)" 4
eq "a host outside the allow-list refused"      "$(BASE=https://evil.example/v1 run >/dev/null 2>&1; echo $?)" 4
eq "…but allowed when listed"                   "$(BASE=https://gw.corp/v1 LITELLM_ALLOW_HOSTS=gw.corp run >/dev/null 2>&1; echo $?)" 0
e="$(FAKE_MODE=err run 2>&1)"; eq "provider error: exit 5" "$(FAKE_MODE=err run >/dev/null 2>&1; echo $?)" 5
eq "…the key is not echoed back"                "$(printf '%s' "$e" | grep -c 'sk-SECRET123')" 0
eq "unexpected response shape: exit 5"          "$(FAKE_MODE=shape run >/dev/null 2>&1; echo $?)" 5
eq "connection failure: exit 5"                 "$(FAKE_MODE=down run >/dev/null 2>&1; echo $?)" 5
eq "no model: refused"                          "$(LITELLM_BASE_URL=http://localhost:4000/v1 LITELLM_EGRESS=allow "$LL" execute --role scout --ro 1 --prompt-file "$T/p" >/dev/null 2>&1; echo $?)" 4
echo "litellm: $pass passed, $failed failed"; [ "$failed" = 0 ]
