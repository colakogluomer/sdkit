#!/usr/bin/env bash
# Quality / cost-proxy regression history over the zero-cost fixture benchmark (F20). Fixture numbers only: no model, no dollars, no tokens.
#   bench/history.sh record [--file F]     run bench/costbase.sh into a temp dir and append one compact line to bench/history.jsonl
#   bench/history.sh check  [--file F]     compare the newest line with the previous one that has the SAME fixture_sha; exit 1 on a regression:
#                                           - any semantic case wrongly accepted (must stay 0)             - avoidable format reruns increased
#                                           - shown bytes of the bounded views grew by more than 10%        - mean selected suites per patch grew by more than 25%
#   bench/history.sh show                  the history, one line per record
# A regression names the metric and the rollback lever (the setting or switch that restores the previous behaviour). A different fixture set is
# reported as "not comparable", never as a pass or a fail.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"; cmd="${1:-}"; shift 2>/dev/null || true; H="$KIT/bench/history.jsonl"
[ "${1:-}" = --file ] && H="$2"
case "$cmd" in
  record) d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT; "$KIT/bench/costbase.sh" capture hist --out "$d" >/dev/null || exit 1
    jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, head:.git.head, dirty:.git.dirty_files, fixture_sha, avoidable_reruns:.verdict_format.avoidable_reruns_with, wrongly_accepted:.verdict_format.wrongly_accepted_with,
      shown_bytes:(.context.tool_output.shown_bytes + .context.role_answer.shown_bytes), mean_selected_suites:.tests.mean_selected_suites}' "$d/hist.costbase.json" >> "$H"; tail -1 "$H" ;;
  check) [ -f "$H" ] || { echo "history: no records yet (bench/history.sh record)"; exit 0; }
    last="$(tail -1 "$H")"; prev="$(sed '$d' "$H" | jq -c --arg f "$(jq -r .fixture_sha <<< "$last")" 'select(.fixture_sha == $f)' | tail -1)"
    [ -n "$prev" ] || { echo "history: no earlier record with the same fixture set; not comparable (neither pass nor fail)"; [ "$(jq .wrongly_accepted <<< "$last")" = 0 ] || { echo "REGRESSION wrongly_accepted=$(jq .wrongly_accepted <<< "$last") (rollback: PARSE_NORMALIZE=0 restores the strict parser)"; exit 1; }; exit 0; }
    bad=0; g() { jq -r "$1" <<< "$2"; }
    [ "$(g .wrongly_accepted "$last")" = 0 ] || { echo "REGRESSION a semantic case was accepted (must be 0); rollback lever: PARSE_NORMALIZE=0 (the strict parser)"; bad=1; }
    [ "$(g .avoidable_reruns "$last")" -le "$(g .avoidable_reruns "$prev")" ] || { echo "REGRESSION avoidable format reruns $(g .avoidable_reruns "$prev") -> $(g .avoidable_reruns "$last"); rollback lever: revert the last parse-verdict.sh change"; bad=1; }
    awk -v a="$(g .shown_bytes "$prev")" -v b="$(g .shown_bytes "$last")" 'BEGIN{exit !(b > a * 1.10)}' && { echo "REGRESSION bounded-view bytes $(g .shown_bytes "$prev") -> $(g .shown_bytes "$last") (>10%); rollback lever: RESULT_ENVELOPE=0 / revert digest.sh"; bad=1; }
    awk -v a="$(g .mean_selected_suites "$prev")" -v b="$(g .mean_selected_suites "$last")" 'BEGIN{exit !(b > a * 1.25)}' && { echo "REGRESSION mean selected suites $(g .mean_selected_suites "$prev") -> $(g .mean_selected_suites "$last") (>25%); rollback lever: revert tests/test-map.conf"; bad=1; }
    [ "$bad" = 0 ] && echo "history: no regression against the previous record (fixtures only; real cost and quality are not measured here)"; exit "$bad" ;;
  show) [ -f "$H" ] && jq -r '"\(.ts) \(.head)\(if .dirty > 0 then "+dirty" else "" end) reruns=\(.avoidable_reruns) wrong=\(.wrongly_accepted) view_bytes=\(.shown_bytes) suites=\(.mean_selected_suites)"' "$H" || echo "history: empty" ;;
  *) echo "usage: history.sh record|check|show [--file F]" >&2; exit 2 ;;
esac
