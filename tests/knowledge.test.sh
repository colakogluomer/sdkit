#!/usr/bin/env bash
# F16 content-hash knowledge notes: fresh while the covered files are unchanged, stale after any change, never offered to independent roles.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"; KN="$KIT/scripts/knowledge.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failed=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else failed=$((failed + 1)); echo "  FAIL $1 (got '$2', wanted '$3')"; fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
R="$T/r"; mkdir -p "$R/.sdkit" "$R/src"; cd "$R" && git init -q . && git config user.email t@t && git config user.name t
printf 'STACK=generic\n' > .sdkit/sdkit.env; echo "a1" > src/a.go; echo "b1" > src/b.go; echo "c1" > src/c.go; git add -A; git commit -qm i
export CLAUDE_PROJECT_DIR="$R"
echo "The importer reads a.go then calls b.go." | "$KN" put t1 importer --files "src/a.go src/b.go" --title "importer flow" >/dev/null
eq "a fresh note is returned"                        "$(rc "$KN" get t1 importer)" 0
eq "…marked untrusted"                               "$("$KN" get t1 importer | head -1 | cut -c1-17)" "UNTRUSTED SUMMARY"
eq "a missing key is a miss (1)"                     "$(rc "$KN" get t1 nothing)" 1
echo "changed" >> src/c.go; git add -A; git commit -qm "unrelated file"
eq "a change to an uncovered file keeps it fresh"    "$(rc "$KN" get t1 importer)" 0
echo "b2" > src/b.go
eq "a change to a covered file makes it stale (1)"   "$(rc "$KN" get t1 importer)" 1
eq "…and names the file"                             "$("$KN" get t1 importer 2>&1 | grep -c 'src/b.go')" 1
echo "b1" > src/b.go; eq "restoring the content makes it fresh again" "$(rc "$KN" get t1 importer)" 0
rm src/a.go; eq "a deleted covered file makes it stale" "$(rc "$KN" get t1 importer)" 1; echo "a1" > src/a.go
for r in verifier reviewer security-auditor verifier-deep; do eq "$r is refused (5)" "$(rc "$KN" get t1 importer --role $r)" 5; done
eq "a developer may use it"                          "$(rc "$KN" get t1 importer --role developer)" 0
eq "a secret-looking note is refused"                "$(echo 'password: hunter2hunter2' | "$KN" put t1 s --files src/a.go >/dev/null 2>&1; echo $?)" 2
eq "an unsafe key is refused"                        "$(echo x | "$KN" put t1 '../x' --files src/a.go >/dev/null 2>&1; echo $?)" 2
eq "list shows fresh"                                "$("$KN" list t1 | grep -c ' fresh ')" 1
echo b3 > src/b.go; eq "list shows stale"            "$("$KN" list t1 | grep -c ' stale ')" 1
"$KN" clear t1 >/dev/null; eq "clear forgets"        "$(rc "$KN" get t1 importer)" 1
echo "knowledge: $pass passed, $failed failed"; [ "$failed" = 0 ]
