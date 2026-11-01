#!/usr/bin/env bash
# Early Definition-of-Done check (F08): run it on proposal.md BEFORE any expensive role (verifier, reviewer) so a DoD the verifier could not
# judge is fixed once, up front, instead of costing a verifier run and a rerun.
# Usage: dod-check.sh <proposal.md|plan.md>
#   Reads the lines   D<n>: <testable condition> | Verified by: <method>   and classifies the method:
#     automated    unit test, integration test, e2e, contract/regression test, automated
#     static       lint, typecheck, static analysis, code inspection, review
#     manual       manual check          (a person must look; never a PASS without recorded evidence)
#     post-deploy  post-deploy / canary / production smoke (cannot be proven before release; never a PASS before it has run)
#     none         "none: <reason>" (the reason is required)
#   An unclassified method is a `warn:` line and counts as manual (never a hard stop: a free-text method is still a method).
#   Problems (exit 1, each printed): no D items, a missing method, `none` without a reason, a duplicate id, an empty condition.
#   Output (exit 0): one line  dod ok: N item(s) automated=a static=s manual=m post-deploy=p none=n  and, when m+p+n > 0, a reminder line.
#   Acceptance (explicit, auditable, never automatic): a manual / post-deploy / none item cannot get a verifier PASS on its own, so without a way out the task
#   would be stuck. A PERSON can accept one item:
#     dod-check.sh accept <proposal.md> D<n> --by "<who>" --reason "<why>"   appends to acceptances.jsonl next to the proposal (committed with it)
#     dod-check.sh accepted <proposal.md> D<n>                              exit 0 only when an acceptance exists FOR THE ITEM AS IT NOW READS
#     dod-check.sh acceptances <proposal.md>                                list them
#   The record binds who, why, when, the DoD id and a hash of the item's text and method: edit the item and the acceptance no longer applies. Only manual,
#   post-deploy and none items can be accepted (automated and static ones need evidence, not consent). Nothing here accepts anything by itself; `--by` and
#   `--reason` are required and no default exists. parse-verdict.sh counts a PASS with evidence `accepted: ...` only when `accepted` succeeds for that item.
# Exit: 0 ok, 1 problems (accepted: no acceptance), 2 usage.
set -u
case "${1:-}" in accept|accepted|acceptances)
  sub="$1"; pf="${2:-}"; did="${3:-}"; shift 3 2>/dev/null || shift $# 2>/dev/null
  [ -f "$pf" ] || { echo "usage: dod-check.sh $sub <proposal.md>${sub:+ D<n>} ..." >&2; exit 2; }
  af="$(dirname "$pf")/acceptances.jsonl"
  item() {  # the item line, whitespace-normalised, and its class
    grep -E "^[[:space:]]*([-*][[:space:]]+)?[*_]*$did[*_]*[.:)]" "$pf" | head -1 | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
  ihash() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
  if [ "$sub" = acceptances ]; then [ -f "$af" ] && cat "$af"; exit 0; fi
  case "$did" in D[0-9]*) ;; *) echo "dod-check: $sub needs a DoD id like D3" >&2; exit 2 ;; esac
  line="$(item)"; [ -n "$line" ] || { echo "dod-check: $did is not in $pf" >&2; exit 1; }
  if [ "$sub" = accepted ]; then
    [ -f "$af" ] || exit 1
    h="$(ihash "$line")"; jq -e --arg d "$did" --arg h "$h" 'select(.id == $d and .item_sha256 == $h)' "$af" >/dev/null 2>&1 && exit 0; exit 1
  fi
  by=""; why=""
  while [ $# -gt 0 ]; do case "$1" in --by) by="${2:-}"; shift ;; --reason) why="${2:-}"; shift ;; *) echo "dod-check: unknown option $1" >&2; exit 2 ;; esac; shift; done
  [ -n "${by//[[:space:]]/}" ] && [ -n "${why//[[:space:]]/}" ] || { echo "dod-check: accept needs --by \"<who accepts>\" and --reason \"<why>\" (nothing is accepted by default)" >&2; exit 2; }
  cls="$(printf '%s\n' "$line" | tr 'A-Z' 'a-z' | sed -nE 's/.*verified by:?[ *_]*//p')"
  case "$cls" in *post-deploy*|*postdeploy*|*canary*|*"production smoke"*|*"after deploy"*|*post-release*|*postrelease*|manual*|*" manual"*|none*) ;; *)
    echo "dod-check: $did is verified by '$cls': only manual, post-deploy or none items can be accepted (the others need evidence)" >&2; exit 1 ;; esac
  mkdir -p "$(dirname "$af")"
  printf '%s\n' "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg d "$did" --arg h "$(ihash "$line")" --arg i "$line" --arg b "$by" --arg r "$why" --arg p "$(basename "$(dirname "$pf")")/$(basename "$pf")" \
    '{v:1, ts:$ts, id:$d, item:$i, item_sha256:$h, by:$b, reason:$r, proposal:$p}')" >> "$af"
  echo "dod-check: $did accepted by $by (recorded in $af); this binds the item as written now"; exit 0 ;;
esac
f="${1:-}"; [ -f "$f" ] || { echo "usage: dod-check.sh proposal.md | accept|accepted|acceptances ..." >&2; exit 2; }
sec="$(awk '/^#+[ \t]/ { if (inside) exit; if (tolower($0) ~ /definition of done/) { inside=1; next } } inside { print }' "$f")"
[ -n "$sec" ] || sec="$(cat "$f")"
printf '%s\n' "$sec" | awk '
  function trim(s) { gsub(/^[ \t*_`]+|[ \t*_`.;,]+$/, "", s); return s }
  match($0, /^[ \t]*([-*][ \t]+)?[*_]*D[0-9]+[*_]*[.:)]/) {
    head = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH + 1)
    id = head; sub(/^[^D]*D/, "", id); sub(/[^0-9].*$/, "", id); id = "D" id
    vb = ""; text = rest
    if (match(tolower(rest), /verified by:?[ \t*_]*/)) { vb = trim(substr(rest, RSTART + RLENGTH)); text = trim(substr(rest, 1, RSTART - 1)); sub(/\|[ \t]*$/, "", text); text = trim(text) }
    else text = trim(rest)
    lv = tolower(vb); cls = ""
    if (id in seen) { print "duplicate id " id; bad++ } seen[id] = 1
    if (text == "") { print id ": empty condition"; bad++ }
    if (vb == "") { print id ": no \"Verified by:\" method"; bad++; next }
    if (lv ~ /^none/) { r = lv; sub(/^none[ \t]*[:\-—–][ \t]*/, "", r); if (r == "" || r == lv) { print id ": \"none\" needs a reason (none: <reason>)"; bad++ } else cls = "none" }
    else if (lv ~ /post-?deploy|canary|production smoke|after deploy|post-?release/) cls = "post-deploy"
    else if (lv ~ /manual/) cls = "manual"
    else if (lv ~ /lint|typecheck|type-check|static|inspection|review|schema check|grep/) cls = "static"
    else if (lv ~ /test|e2e|automated|contract|regression|benchmark|assert/) cls = "automated"
    else { print "warn: " id ": unclassified method \"" vb "\", counted as manual (it needs recorded evidence; prefer automated|static|manual|post-deploy|none: reason)"; cls = "manual" }
    if (cls != "") c[cls]++
    n++
  }
  END {
    if (n == 0) { print "no DoD items (D<n>: ... | Verified by: ...) found"; exit 1 }
    if (bad > 0) { exit 1 }
    printf "dod ok: %d item(s) automated=%d static=%d manual=%d post-deploy=%d none=%d\n", n, c["automated"], c["static"], c["manual"], c["post-deploy"], c["none"]
    if (c["manual"] + c["post-deploy"] + c["none"] > 0) print "note: manual / post-deploy / none items are not satisfied by a verifier PASS without recorded evidence; plan how each is evidenced or accepted."
  }'
