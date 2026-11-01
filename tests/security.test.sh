#!/usr/bin/env bash
# F19: secret redaction, the hash-chained audit trail, egress audited before it happens, and the shipped enforcement checked statically. No model, no network.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"; RD="$KIT/scripts/redact.sh"; AU="$KIT/scripts/audit.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }
mkdir -p "$T/p/.sdkit"; export CLAUDE_PROJECT_DIR="$T/p"; cd "$T/p" && git init -q .

echo "redaction"
r() { printf '%s\n' "$1" | "$RD"; }
eq "aws key id"            "$(r 'id AKIAABCDEFGHIJKLMNOP end')" "id [REDACTED:aws-key-id] end"
eq "github token"          "$(r 'x ghp_abcdefghijklmnopqrstuvwx y')" "x [REDACTED:github-token] y"
eq "sk- api key"           "$(r 'key sk-ant-abcdefghijklmnop1234')" "key [REDACTED:api-key]"
eq "bearer header"         "$(r 'Authorization: Bearer abcdef0123456789xyz')" "Authorization: Bearer [REDACTED:bearer]"
eq "password assignment"   "$(r 'password = hunter2hunter2')" "password = [REDACTED:value]"
eq "jwt"                   "$(r 'tok eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.abcdefghijkl end')" "tok [REDACTED:jwt] end"
eq "private key block"     "$(printf 'a\n-----BEGIN RSA PRIVATE KEY-----\nMIIB\n-----END RSA PRIVATE KEY-----\nb\n' | "$RD" | tr '\n' ,)" "a,[REDACTED:private-key],b,"
eq "ordinary text passes unchanged" "$(r 'the retry count is 3 and the token bucket is full')" "the retry count is 3 and the token bucket is full"

echo "audit trail"
"$AU" log egress adapter=litellm host=gw.corp bytes=120 >/dev/null; "$AU" log budget.override role=developer >/dev/null; "$AU" log policy.fail note="key sk-abcdefghijklmnopqrstuv leaked" >/dev/null
eq "chain verifies"                        "$("$AU" verify | cut -c1-15)" "audit: chain ok"
eq "a secret in a value is redacted"       "$(grep -c 'sk-abcdefghijklmnop' .sdkit/audit.jsonl)" 0
eq "long (content-like) values refused"    "$("$AU" log egress prompt="$(printf 'x%.0s' $(seq 1 200))" >/dev/null 2>&1; echo $?)" 2
eq "a bad type is refused"                 "$("$AU" log 'Bad Type' >/dev/null 2>&1; echo $?)" 2
cp .sdkit/audit.jsonl "$T/keep"
sed -i.bak 's/gw.corp/evil.example/' .sdkit/audit.jsonl; rm -f .sdkit/audit.jsonl.bak
eq "an edited line breaks the chain (1)"   "$("$AU" verify >/dev/null 2>&1; echo $?)" 1
cp "$T/keep" .sdkit/audit.jsonl; sed -i.bak '2d' .sdkit/audit.jsonl; rm -f .sdkit/audit.jsonl.bak
eq "a deleted middle line breaks it"       "$("$AU" verify >/dev/null 2>&1; echo $?)" 1
cp "$T/keep" .sdkit/audit.jsonl
eq "show filters by type"                  "$("$AU" show --type egress | wc -l | tr -d ' ')" 1

echo "egress is audited first"
mkdir -p "$T/bin"; printf '#!/bin/sh\ncat >/dev/null; echo "{\\"choices\\":[{\\"message\\":{\\"content\\":\\"ok\\"}}]}"\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"; printf hello > "$T/prompt"
run() { PATH="$T/bin:$PATH" LITELLM_BASE_URL=http://localhost:4000/v1 LITELLM_MODEL=m LITELLM_EGRESS=allow "$KIT/adapters.d/litellm.sh" execute --role scout --ro 1 --prompt-file "$T/prompt"; }
n0="$(wc -l < .sdkit/audit.jsonl | tr -d ' ')"; run >/dev/null 2>&1
eq "an egress request writes one audit record"     "$(( $(wc -l < .sdkit/audit.jsonl | tr -d ' ') - n0 ))" 1
eq "…with host and byte count, no prompt text"     "$(tail -1 .sdkit/audit.jsonl | jq -r '[.type, .host, .bytes] | join(",")')" "egress,localhost:4000,5"
eq "…and not the prompt"                           "$(tail -1 .sdkit/audit.jsonl | grep -c hello)" 0
rm .sdkit/audit.jsonl; mkdir .sdkit/audit.jsonl
eq "no audit record, no egress (exit 4)"           "$(run >/dev/null 2>&1; echo $?)" 4
rmdir .sdkit/audit.jsonl

echo "views are redacted, the full text on disk is not"
printf 'line\nsecret = abcdefgh1234\n' > "$T/o"; for i in $(seq 1 80); do echo "row $i" >> "$T/o"; done
"$KIT/scripts/digest.sh" output --ref "$T/full" < "$T/o" > "$T/view"
eq "the view hides the value"                      "$(grep -c abcdefgh1234 "$T/view")" 0
eq "the full text keeps it (evidence is intact)"   "$(grep -c abcdefgh1234 "$T/full")" 1

echo "shipped enforcement (static)"
eq "audit.sh policy passes on the kit"             "$("$AU" policy >/dev/null 2>&1; echo $?)" 0
cp -R "$KIT" "$T/kit" 2>/dev/null; rm -rf "$T/kit/.git"
sed -i.bak 's/^tools: Read, Grep, Glob, Bash/tools: Read, Grep, Glob, Bash, Edit/' "$T/kit/agents/verifier.md"
eq "a read-only role given Edit is caught"         "$("$T/kit/scripts/audit.sh" policy >/dev/null 2>&1; echo $?)" 1
cp -R "$KIT/agents" "$T/kit/"; sed -i.bak 's/guard-secrets.sh//' "$T/kit/hooks/hooks.json"
eq "an unwired guard hook is caught"               "$("$T/kit/scripts/audit.sh" policy 2>&1 | grep -c 'guard-secrets')" 1
echo "security: $pass passed, $failed failed"; [ "$failed" = 0 ]
