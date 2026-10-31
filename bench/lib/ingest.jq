# Normalize one agent-metrics/1 object (jq -f, --argjson prices '{model:{in,out,cache_read,cache_write}}' = USD per million tokens).
# Rules: a missing or invalid number becomes null (never 0) and the field is "unavailable"; a number without a quality label is
# "estimated", never "measured"; provider cost and billing mode stay apart (subscription billing has no metered spend).
def nn: if type == "number" and . >= 0 and . == floor then . else null end;
def usd: if type == "number" and . >= 0 then . else null end;
def qlab: if . == "measured" or . == "estimated" then . else null end;
def bad($raw; $norm; $name): if $raw != null and $norm == null then "invalid " + $name + " (" + ($raw | tojson) + ") ignored" else empty end;
(if type == "object" then . else {} end) as $m
| ($m.tokens // {}) as $t
| ($t | if type == "object" then . else {} end) as $t
| {in: ($t.in | nn), out: ($t.out | nn), cache_read: ($t.cache_read | nn), cache_write: ($t.cache_write | nn)} as $tk
| ($tk.in != null and $tk.out != null) as $have
| ($m.tokens_quality) as $claim
| (if $claim == "unavailable" then false else $have end) as $use
| (if $use then ($claim | qlab) // "estimated" else "unavailable" end) as $tq
| (if $use then $tk else {in: null, out: null, cache_read: null, cache_write: null} end) as $tok
| (if $use then ($tok.in + $tok.out + ($tok.cache_read // 0) + ($tok.cache_write // 0)) else null end) as $total
| (($m.billing // "unknown") | if . == "metered" or . == "subscription" then . else "unknown" end) as $billing
| ($m.cost // {} | if type == "object" then . else {} end) as $c
| ($c.provider_usd | usd) as $prov_in
| ($c.estimated_usd | usd) as $est_in
| (if $billing == "subscription" then null else $prov_in end) as $prov
| ($m.model // null) as $model
| (if $est_in != null then $est_in
   elif $billing == "subscription" and $prov_in != null then $prov_in
   elif $use and $tq == "measured" and $model != null and ($prices[$model] != null)
     then (($tok.in * ($prices[$model].in // 0) + $tok.out * ($prices[$model].out // 0)
            + ($tok.cache_read // 0) * ($prices[$model].cache_read // 0) + ($tok.cache_write // 0) * ($prices[$model].cache_write // 0)) / 1000000)
   else null end) as $est
| ($m.quality // {} | if type == "object" then . else {} end) as $ql
| def cnt($k): ($m[$k] | nn) as $v | {value: $v, q: (if $v == null then "unavailable" else (($ql[$k] | qlab) // "estimated") end)};
  cnt("llm_calls") as $llm | cnt("agent_calls") as $ag | cnt("retries") as $re
| ([($m.phases // []) | if type == "array" then .[] else empty end
     | select(type == "object" and (.name | type) == "string" and (.dur_s | usd) != null) | {name, dur_s}]) as $ph
| ([($m.roles // {}) | if type == "object" then to_entries[] else empty end
     | select(.value | type == "object")
     | {key, value: {in: (.value.in | nn), out: (.value.out | nn), cache_read: (.value.cache_read | nn), cache_write: (.value.cache_write | nn), calls: (.value.calls | nn)}}] | from_entries) as $roles
| {
    schema: "tbench-metrics/1",
    source: ($m.source // "unknown"),
    model: $model, provider: ($m.provider // null), billing: $billing,
    tokens: {in: $tok.in, out: $tok.out, cache_read: $tok.cache_read, cache_write: $tok.cache_write, total: $total,
             total_basis: (if $total == null then null elif $tok.cache_read != null and $tok.cache_write != null then "all-four" else "in+out(+known cache); a lower bound" end),
             quality: $tq},
    cost: {provider_usd: $prov, provider_quality: (if $prov != null then "measured" else "unavailable" end),
           estimated_usd: $est, estimated_quality: (if $est != null then "estimated" else "unavailable" end)},
    llm_calls: $llm.value, agent_calls: $ag.value, retries: $re.value,
    phases: (if ($ph | length) > 0 then $ph else null end),
    roles: (if ($roles | length) > 0 then $roles else null end),
    completeness: {tokens: $tq, cost_provider: (if $prov != null then "measured" else "unavailable" end),
                   cost_estimated: (if $est != null then "estimated" else "unavailable" end),
                   llm_calls: $llm.q, agent_calls: $ag.q, retries: $re.q,
                   phases: (if ($ph | length) > 0 then "measured" else "unavailable" end),
                   roles: (if ($roles | length) > 0 then "measured" else "unavailable" end)},
    warnings: ([ ($m.warnings_in // [])[],
                 (if ($m | length) == 0 then "no metrics reported by the run" else empty end),
                 (if $claim == "unavailable" and $have then "numbers present but the source says unavailable: ignored" else empty end),
                 (if $use and $claim == null then "token usage has no quality label: recorded as estimated" else empty end),
                 (if $claim == "measured" and ($have | not) then "tokens labeled measured but in/out missing: recorded as unavailable" else empty end),
                 bad($t.in; $tk.in; "tokens.in"), bad($t.out; $tk.out; "tokens.out"),
                 bad($t.cache_read; $tk.cache_read; "tokens.cache_read"), bad($t.cache_write; $tk.cache_write; "tokens.cache_write"),
                 bad($c.provider_usd; $prov_in; "cost.provider_usd"), bad($c.estimated_usd; $est_in; "cost.estimated_usd"),
                 bad($m.llm_calls; $llm.value; "llm_calls"), bad($m.agent_calls; $ag.value; "agent_calls"), bad($m.retries; $re.value; "retries"),
                 (if $billing == "subscription" and $prov_in != null then "subscription billing: the reported USD is API-equivalent, kept as estimated cost, not as spend" else empty end),
                 (if $use and ($tok.cache_read == null or $tok.cache_write == null) then "host reports no cache counts: total is a lower bound" else empty end)
               ] | unique)
  }
