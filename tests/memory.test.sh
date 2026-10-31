#!/usr/bin/env bash
# scripts/memory.sh: off by default, entries, index cap, secrets refused, search, stale, promotion from task notes.
# Run: tests/memory.test.sh
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi; }
nocheck() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$n"; else ok "$n"; fi; }
M="$KIT/scripts/memory.sh"

cd "$T" && git init -q -b main . && echo r > README.md && mkdir .claude && printf 'BASE_BRANCH=main\n' > .claude/project.env
echo "off by default"
check   "off: add is a silent no-op (exit 0)"      "$M" add fact a --title x
check   "off: no directory is created"             test ! -d .claude/memory
check   "off: autoload prints nothing"             test -z "$("$M" autoload)"
check   "off: status says off"                     bash -c "'$M' status | grep -q 'memory: off'"

printf 'MEMORY=1\nMEMORY_INDEX_MAX=3\nMEMORY_STALE_DAYS=30\n' >> .claude/project.env
echo "entries"
check   "init creates INDEX.md"                    bash -c "'$M' init && test -f .claude/memory/INDEX.md"
check   "add a fact"                               "$M" add fact payments-api --title "Payments API is idempotent on order id" --body "Retry is safe." --refs README.md
check   "entry file has frontmatter"               grep -q '^type: fact' .claude/memory/payments-api.md
check   "INDEX lists the entry"                    grep -q '\[fact\] payments-api: Payments API' .claude/memory/INDEX.md
nocheck "duplicate slug refused"                   "$M" add fact payments-api --title again
nocheck "bad type refused"                         "$M" add story s --title x
nocheck "bad slug refused"                         "$M" add fact '../x' --title x
nocheck "missing title refused"                    "$M" add fact notitle
nocheck "secret in body refused"                   "$M" add fact leak --title t --body "password=hunter2hunter2"
nocheck "private key refused"                      "$M" add fact leak2 --title t --body "-----BEGIN RSA ""PRIVATE KEY-----"
check   "body from stdin"                          bash -c "echo 'run make seed first' | '$M' add howto seed --title 'Seed the db' --body -"
check   "stdin body stored"                        grep -q 'make seed' .claude/memory/seed.md
check   "decision type accepted"                   "$M" add decision use-uuid --title "Ids are UUIDv7"
nocheck "index cap refuses the 4th entry"          "$M" add fact fourth --title x
check   "cap leaves no half-written file"          test ! -f .claude/memory/fourth.md

echo "index, search, autoload"
rm .claude/memory/INDEX.md
check   "index rebuilds from entry files"          bash -c "'$M' index && grep -c '^- \[' .claude/memory/INDEX.md | grep -q '^3\$'"
printf 'known\n' > .claude/known-pitfalls.md; mkdir -p .claude/adr
check   "INDEX links known-pitfalls and adr"       bash -c "'$M' index && grep -q 'known-pitfalls.md' .claude/memory/INDEX.md && grep -q 'adr/' .claude/memory/INDEX.md"
check   "search finds a body line"                 bash -c "'$M' search 'make seed' | grep -q seed.md"
check   "search ignores frontmatter bookkeeping"   test -z "$("$M" search 'verify-by')"
check   "autoload prints the index"                bash -c "'$M' autoload | grep -q 'Knowledge index'"
check   "autoload is trimmed to MEMORY_INDEX_MAX"  test "$("$M" autoload | wc -l | tr -d ' ')" -le 3
check   "MEMORY_AUTOLOAD=0 silences autoload"      test -z "$(MEMORY_AUTOLOAD=0 "$M" autoload)"

echo "stale"
check   "fresh entries are not stale"              test -z "$("$M" stale | grep -v seed)"
sed -i.bak 's/^updated:.*/updated: 2020-01-01/' .claude/memory/seed.md && rm .claude/memory/seed.md.bak
check   "old entry is stale"                       bash -c "'$M' stale | grep -q '^seed:.*older than 30 days'"
sed -i.bak 's/^refs:.*/refs: no\/such\/file.go/' .claude/memory/use-uuid.md && rm .claude/memory/use-uuid.md.bak
check   "missing ref is stale"                     bash -c "'$M' stale | grep -q '^use-uuid:.*no/such/file.go is gone'"
sed -i.bak 's/^verify-by:.*/verify-by: 2020-06-01/' .claude/memory/payments-api.md && rm .claude/memory/payments-api.md.bak
check   "passed verify-by is stale"                bash -c "'$M' stale | grep -q '^payments-api:.*verify-by'"

echo "promotion from task notes"
rm -f .claude/memory/*.md; "$M" init >/dev/null
mkdir -p .claude/work/t1
printf 'free text\nMEMORY: fact | queue-order | Queue is FIFO per key | Ordered per partition key only.\nMEMORY: howto | local-run | Run locally | make up\n' > .claude/work/t1/notes.md
check   "candidates are numbered"                  bash -c "'$M' candidates t1 | grep -q '^2: howto | local-run'"
check   "promote one candidate"                    "$M" promote t1 1
check   "chosen candidate became an entry"         grep -q 'Ordered per partition' .claude/memory/queue-order.md
check   "unchosen candidate was not added"         test ! -f .claude/memory/local-run.md
check   "promote all"                              bash -c "'$M' promote t1 all; test -f .claude/memory/local-run.md"
nocheck "promote exits 1 when a candidate cannot be added" bash -c "'$M' promote t1 1"
check   "no notes file is not an error"            "$M" candidates nosuch
sed -i.bak 's/^MEMORY=1/MEMORY=1\nMEMORY_PROMOTE=off/' .claude/project.env && rm .claude/project.env.bak
check   "MEMORY_PROMOTE=off lists nothing"         test -z "$("$M" candidates t1 2>/dev/null)"

echo "memory tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
