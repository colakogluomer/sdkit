# telemetry.sh summary --json  ->  agent-metrics/1 (then lib/ingest.jq). Nothing is invented: what telemetry cannot say stays null.
def q: if . == "actual" then "measured" elif . == "estimated" then "estimated" elif . == "mixed" then "estimated" else "unavailable" end;
. as $s
| if ($s | type) != "object" or ($s.error // null) != null then {} else
  ($s.tokens.runs_measured // 0) as $meas
  | (($s.tokens.cache_read // 0) > 0 or ($s.tokens.cache_write // 0) > 0) as $cache
  | {
      source: "telemetry-summary",
      tokens: (if $meas > 0 then {in: $s.tokens.in, out: $s.tokens.out,
                                  cache_read: (if $cache then $s.tokens.cache_read else null end),
                                  cache_write: (if $cache then $s.tokens.cache_write else null end)} else null end),
      tokens_quality: ($s.tokens.quality | q),
      cost: {estimated_usd: ($s.cost.usd // null)},
      agent_calls: ($s.agents.spawned // null), retries: ($s.retries // null),
      quality: {agent_calls: "measured", retries: "measured"},
      phases: [($s.phases // [])[] | select(.dur_s != null) | {name: .phase, dur_s: .dur_s}],
      roles: ([($s.agents.by_role // [])[] | select(.in != null and (.runs_without_tokens // 0) < .runs)
               | {key: .role, value: {in, out, cache_read, cache_write, calls: .runs}}] | from_entries),
      warnings_in: [ (if ($s.tokens.complete // false) | not then "telemetry: token totals cover " + (($meas) | tostring) + " of " + (($s.agents.finished // 0) | tostring) + " agent runs (lower bound)" else empty end),
                     (if $meas > 0 and ($cache | not) then "telemetry: cache counts are 0 or absent: treated as unavailable" else empty end),
                     "telemetry does not count LLM invocations: llm_calls unavailable" ]
    } end
