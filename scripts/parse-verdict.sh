#!/usr/bin/env bash
# Validate a verifier's output block and turn it into a decision.
# Usage: parse-verdict.sh <file|-> [--proposal proposal.md] [--record] [--role verifier|reviewer|security-auditor] [--source S --run ID --task SLUG]
#   Checks the DOD / FINDINGS / VERIFY / VERDICT structure, that every DoD line is PASS|FAIL, every finding is
#   CONFIRMED|PLAUSIBLE, and that VERDICT agrees with the rule (BLOCK iff any FAIL or any CONFIRMED).
#   --record stores a well-formed verdict in the workflow state (scripts/sdd.sh), bound to the current diff; hosts without a
#   SubagentStop hook use it. A malformed block records nothing.
#   With --proposal also checks the verifier judged as many DoD items as the proposal lists (no skipped items).
#   --role reviewer|security-auditor (F04) checks that role's own block: its finding lines, a SUMMARY line whose counts match them, and one
#   VERDICT: PASS|BLOCK that agrees (reviewer: BLOCK iff a BLOCKER; security-auditor: BLOCK iff a CRITICAL or HIGH finding).
#   --source/--run/--task say who produced the answer (hook and run-role.sh pass them; sdd.sh checks them against its spawn registry, a bare --record is recorded as manual).
# Prints one summary line. Exit: 0 PASS, 1 BLOCK, 2 malformed or inconsistent (ask the role for the format again, once),
#   3 well-formed but sdd.sh refused to record it (stale, duplicate, unknown run ...; the reason is printed on a second line).
set -u
src="${1:--}"; proposal=""; record=0; role=verifier; source=""; run=""; etask=""; shift
while [ $# -gt 0 ]; do case "$1" in --proposal) proposal="${2:-}"; shift ;; --record) record=1 ;; --role) role="${2:-}"; shift ;; --source) source="${2:-}"; shift ;; --run) run="${2:-}"; shift ;; --task) etask="${2:-}"; shift ;; esac; shift; done
text="$(cat "$src")" || exit 2
# F08: the block is normalised first, by deterministic rules that cannot change a judgement: CR line ends, markdown emphasis around a marker or
# a PASS|FAIL|BLOCK|CONFIRMED|PLAUSIBLE token, lower-case tokens, `*`/`1.` bullets as `-`. Nothing is inferred: a missing token stays missing.
[ "${PARSE_NORMALIZE:-1}" = 0 ] || text="$(printf '%s\n' "$text" | tr -d '\r' | awk '
  { l = $0
    if (match(l, /^[ \t]*[*_]+(DOD|FINDINGS|VERIFY|SUMMARY)[*_]*:?[ \t]*$/)) { gsub(/[ \t*_:]/, "", l) }
    else if (match(l, /^[ \t]*[*_]*VERDICT[*_]*[ \t]*:?[*_ \t]*:?[ \t]*[*_`]*[A-Za-z]+[*_`]*[ \t]*$/)) { v = l; gsub(/^[ \t]*[*_]*VERDICT[*_]*[ \t]*:?[*_ \t]*:?[ \t]*[*_`]*|[*_`]*[ \t]*$/, "", v); l = "VERDICT: " toupper(v) }
    else if (l ~ /\|[ \t]*[*_]*(pass|fail|PASS|FAIL|Pass|Fail)[*_]*[ \t]*(\||$)/) {
      n = split(l, f, "|"); for (i = 2; i <= n; i++) { t = f[i]; gsub(/[ \t*_]/, "", t); if (toupper(t) == "PASS" || toupper(t) == "FAIL") { f[i] = " " toupper(t) " "; break } }
      l = f[1]; for (i = 2; i <= n; i++) l = l "|" f[i] }
    if (match(l, /^[ \t]*([-*]|[0-9]+[.)])[ \t]+[*_]*(confirmed|plausible|Confirmed|Plausible)[*_]*[ \t]*\|/)) { t = l; sub(/^[ \t]*([-*]|[0-9]+[.)])[ \t]+[*_]*/, "", t); w = t; sub(/[*_]*[ \t]*\|.*$/, "", w); sub(/^[^|]*/, "", t); l = "- " toupper(w) " " t }
    sub(/^[ \t]*[*][ \t]+/, "- ", l); sub(/^[ \t]*[0-9]+[.)][ \t]+/, "- ", l)
    print l }')"
# PARSE_NORMALIZE=0 skips the normalisation (the pre-F08 behaviour; bench/costbase.sh uses it as the baseline arm)
# kind says what a malformed answer is: `format` = shape only (a bounded re-ask of the same question is enough), `semantic` = the content contradicts
# itself or lacks evidence (re-asking the same thing is not a fix; the judgement is never edited here)
kind=format
bad() { echo "MALFORMED[$kind]: $*"; exit 2; }
semantic() { kind=semantic; bad "$@"; }
record_it() {  # <verdict>: hand a well-formed verdict to the phase machine; 3 when it refuses, silent when no task is open
  local ev=() out rc
  [ -n "$source" ] && ev+=(--source "$source"); [ -n "$run" ] && ev+=(--run "$run"); [ -n "$etask" ] && ev+=(--task "$etask")
  out="$("$(dirname "$0")/sdd.sh" _evidence "$role" "$1" ${ev[@]+"${ev[@]}"} 2>&1)"; rc=$?
  [ "$rc" = 1 ] && { echo "$1 well-formed, NOT recorded: $out"; return 3; }
  return 0
}
case "$role" in verifier|reviewer|security-auditor) ;; *) bad "unknown --role '$role'" ;; esac

if [ "$role" != verifier ]; then
  blk="$(printf '%s\n' "$text" | grep -v '^[[:space:]]*```')"
  if [ "$role" = reviewer ]; then sevs="BLOCKER MAJOR MINOR"; blocking="BLOCKER"; else sevs="CRITICAL HIGH MEDIUM LOW"; blocking="CRITICAL HIGH"; fi
  counts=""; nblock=0; total=0
  for sv in $sevs; do
    c="$(printf '%s\n' "$blk" | grep -cE "^[[:space:]]*([-*]|[0-9]+[.)])?[[:space:]]*[*_]*$sv[*_]*[[:space:]]*\\|" || true)"; counts="$counts $c"; total=$((total + c))
    case " $blocking " in *" $sv "*) nblock=$((nblock + c)) ;; esac
  done
  counts="${counts# }"
  if [ "$role" = reviewer ]; then sumre='^SUMMARY:[[:space:]]*([0-9]+) blockers?, ([0-9]+) major, ([0-9]+) minor[[:space:]]*$'
  else sumre='^SUMMARY:[[:space:]]*([0-9]+) critical, ([0-9]+) high, ([0-9]+) medium, ([0-9]+) low[[:space:]]*$'; fi
  [ "$(printf '%s\n' "$blk" | grep -c '^SUMMARY:')" = 1 ] || bad "$role output needs exactly one SUMMARY line"
  sline="$(printf '%s\n' "$blk" | grep -E "$sumre" | head -1)"; [ -n "$sline" ] || bad "SUMMARY line is not in the $role format"
  said="$(printf '%s\n' "$sline" | sed -E 's/^SUMMARY:[[:space:]]*//; s/[^0-9]+/ /g; s/^ //; s/ $//')"
  [ "$said" = "$counts" ] || semantic "SUMMARY says '$said' but the findings count '$counts'"
  if [ "$role" = security-auditor ]; then
    nof="$(printf '%s\n' "$blk" | grep -cE '^[[:space:]]*NO FINDINGS' || true)"
    { [ "$total" = 0 ] && [ "$nof" -ge 1 ]; } || { [ "$total" -gt 0 ] && [ "$nof" = 0 ]; } || bad "NO FINDINGS must appear exactly when there are no findings"
  fi
  [ "$(printf '%s\n' "$blk" | grep -cE '^[[:space:]]*[*_]*VERDICT')" = 1 ] || bad "$role output needs exactly one VERDICT line"
  l_s="$(printf '%s\n' "$blk" | grep -n '^SUMMARY:' | cut -d: -f1)"; l_v="$(printf '%s\n' "$blk" | grep -n '^VERDICT:' | cut -d: -f1)"
  [ "$l_s" -lt "$l_v" ] || bad "VERDICT must come after SUMMARY"
  verdict="$(printf '%s\n' "$blk" | sed -n "${l_v}p" | sed -E 's/^VERDICT:[[:space:]]*//; s/[[:space:]]+$//')"
  case "$verdict" in PASS|BLOCK) ;; *) bad "VERDICT must be PASS or BLOCK, got '$verdict'" ;; esac
  expect=PASS; [ "$nblock" -gt 0 ] && expect=BLOCK
  [ "$verdict" = "$expect" ] || semantic "VERDICT is $verdict but $nblock blocking finding(s) require $expect"
  echo "VERDICT=$verdict role=$role findings=$total blocking=$nblock"
  if [ "$record" = 1 ]; then record_it "$verdict" || exit 3; fi
  [ "$verdict" = PASS ]; exit
fi

block="$(printf '%s\n' "$text" | grep -v '^[[:space:]]*```' )"
lineno() { printf '%s\n' "$block" | grep -n -m1 -E "$1" | cut -d: -f1; }
l_dod="$(lineno '^DOD[[:space:]]*$')"; l_find="$(lineno '^FINDINGS[[:space:]]*$')"
l_ver="$(lineno '^VERIFY[[:space:]]*$')"; l_verdict="$(lineno '^VERDICT:')"
[ -n "$l_dod" ] && [ -n "$l_find" ] && [ -n "$l_ver" ] && [ -n "$l_verdict" ] || bad "missing a DOD / FINDINGS / VERIFY / VERDICT marker"
[ "$l_dod" -lt "$l_find" ] && [ "$l_find" -lt "$l_ver" ] && [ "$l_ver" -lt "$l_verdict" ] || bad "sections are out of order"

section() { printf '%s\n' "$block" | sed -n "$(( $1 + 1 )),$(( $2 - 1 ))p" | grep -E '^[[:space:]]*-' || true; }
dod="$(section "$l_dod" "$l_find")"; finds="$(section "$l_find" "$l_ver")"; ver="$(section "$l_ver" "$l_verdict")"

[ -n "$dod" ] || bad "DOD has no items"
pass=0; fail=0; accepted=0
while IFS= read -r l; do
  case "$l" in
    *"| PASS |"*|*"| PASS"|*"|PASS|"*)
      # F08: a PASS carries evidence. "manual", "post-deploy", "n/a" or nothing is not evidence, so it never counts as a pass
      ev="$(printf '%s\n' "$l" | sed -E 's/^.*\|[[:space:]]*PASS[[:space:]]*\|?[[:space:]]*//; s/[[:space:]]+$//' | tr 'A-Z' 'a-z')"
      # (This is a heuristic filter on the answer's TEXT, not proof that the evidence is real: the independent run, the diff binding and the verify command are the proof.)
      # The one non-test evidence there is: `accepted: <by>` for a manual / post-deploy / none item that a person accepted (dod-check.sh accept), checked against the record.
      case "$ev" in accepted|accepted[:\ ]*)
          aid="$(printf '%s\n' "$l" | grep -oE 'D[0-9]+' | head -1)"; dc="$(dirname "$0")/dod-check.sh"
          [ -n "$proposal" ] && [ -f "$proposal" ] && [ -n "$aid" ] && [ -x "$dc" ] && "$dc" accepted "$proposal" "$aid" \
            || semantic "PASS claims an acceptance, but no person's acceptance is recorded for ${aid:-this item} as it now reads (dod-check.sh accept; needs --proposal): $l"
          accepted=$((accepted + 1)) ;; esac
      case "$ev" in ''|'-'|n/a|na|manual|manual.|post-deploy|postdeploy|pending|tbd|todo|none|*"not verified"*) semantic "PASS without evidence (a manual, post-deploy or empty item is not a pass; use FAIL, or give file:line / test name): $l" ;; esac
      pass=$((pass + 1)) ;;
    *"| FAIL |"*|*"| FAIL"|*"|FAIL|"*) fail=$((fail + 1)) ;;
    *) bad "DoD line without PASS|FAIL: $l" ;;
  esac
done <<< "$dod"

conf=0; plaus=0
if [ -n "$finds" ]; then
  while IFS= read -r l; do
    case "$l" in
      -[[:space:]]CONFIRMED[[:space:]]*\|*) conf=$((conf + 1)) ;;
      -[[:space:]]PLAUSIBLE[[:space:]]*\|*) plaus=$((plaus + 1)) ;;
      -[[:space:]][Nn]one*) ;;
      *) bad "finding without CONFIRMED|PLAUSIBLE: $l" ;;
    esac
  done <<< "$finds"
fi
[ -n "$ver" ] || bad "VERIFY has no command line"
printf '%s\n' "$ver" | grep -qE 'result:[[:space:]]*(green|red)' || bad "VERIFY line lacks 'result: green|red'"

verdict="$(printf '%s\n' "$block" | sed -n "${l_verdict}p" | sed -E 's/^VERDICT:[[:space:]]*//; s/[[:space:]]+$//')"
case "$verdict" in PASS|BLOCK) ;; *) bad "VERDICT must be PASS or BLOCK, got '$verdict'" ;; esac
expect=PASS; { [ "$fail" -gt 0 ] || [ "$conf" -gt 0 ]; } && expect=BLOCK
[ "$verdict" = "$expect" ] || semantic "VERDICT is $verdict but $fail FAIL item(s) and $conf CONFIRMED finding(s) require $expect"

if [ -n "$proposal" ]; then
  [ -f "$proposal" ] || bad "proposal not found: $proposal"
  want="$(grep -cE '^[[:space:]]*([-*][[:space:]]+)?[*_]*D[0-9]+[*_]*[.:)]' "$proposal" || true)"
  got=$((pass + fail))
  [ "$want" -eq 0 ] || [ "$want" -eq "$got" ] || semantic "proposal lists $want DoD items, verifier judged $got (skipped items)"
fi

echo "VERDICT=$verdict dod_pass=$pass dod_fail=$fail confirmed=$conf plausible=$plaus$([ "$accepted" -gt 0 ] && echo " accepted=$accepted")"
if [ "$record" = 1 ]; then record_it "$verdict" || exit 3; fi
[ "$verdict" = PASS ]
