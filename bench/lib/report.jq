# Aggregate sealed run results (jq -f, --argjson min_n N --argjson integrity '{tampered:[],incomplete:[]}'); input = array of tbench-result/1.
# Failures stay in every denominator. Missing measurements are counted as missing, never as 0. Nothing here ranks strategies.
def known: map(select(. != null));
def median: known | sort | (length) as $n | if $n == 0 then null elif $n % 2 == 1 then .[($n - 1) / 2] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
def total: known | if length == 0 then null else add end;
def r2: if . == null then null else (. * 100 | round) / 100 end;
def r4: if . == null then null else (. * 10000 | round) / 10000 end;

# a metric over a group of runs: how many have it, and the numbers only when it is known for EVERY run (else the sum would be a silent undercount)
def metric(f): (map(f)) as $v | ($v | known | length) as $k
  | {runs: length, known: $k, complete: (length > 0 and $k == length), median: ($v | median | r2), sum: (if length > 0 and $k == length then ($v | total | r2) else null end)};

def per_success($m; $succ; $n):
  if $succ == 0 then {value: null, reason: "no successful run"}
  elif $n < $min_n then {value: null, reason: "sample too small (n=\($n) < \($min_n))"}
  elif ($m.complete | not) then {value: null, reason: "metric unavailable for \($m.runs - $m.known) of \($m.runs) runs"}
  else {value: ($m.sum / $succ | r2), reason: null} end;

def group_stats:
  (length) as $n | (map(select(.success))) as $ok
  | metric(.metrics.tokens.total) as $tok | metric(.metrics.cost.provider_usd) as $cp | metric(.metrics.cost.estimated_usd) as $ce
  | {
      runs: $n, successes: ($ok | length), failures: ($n - ($ok | length)),
      success_rate: (if $n == 0 then null else (($ok | length) / $n | r4) end),
      failure_categories: (map(select(.success | not) | .failure_category // "unknown") | group_by(.) | map({key: .[0], value: length}) | from_entries),
      tokens_total: $tok, tokens_total_successful_runs: ($ok | metric(.metrics.tokens.total)),
      cost_provider_usd: $cp, cost_estimated_usd: $ce,
      cost_per_success: {tokens: per_success($tok; ($ok | length); $n), provider_usd: per_success($cp; ($ok | length); $n), estimated_usd: per_success($ce; ($ok | length); $n)},
      duration_s: metric(.duration_s), retries: metric(.metrics.retries), agent_calls: metric(.metrics.agent_calls), llm_calls: metric(.metrics.llm_calls),
      public_pass: (map(select(.evaluation.public.outcome == "pass")) | length), hidden_pass: (map(select(.evaluation.hidden.outcome == "pass")) | length),
      completeness: (. as $runs | [ "tokens", "cost_provider", "cost_estimated", "llm_calls", "agent_calls", "retries", "phases", "roles" ] | map(. as $f
        | {key: $f, value: {measured: ($runs | map(select(.metrics.completeness[$f] == "measured")) | length), estimated: ($runs | map(select(.metrics.completeness[$f] == "estimated")) | length), unavailable: ($runs | map(select((.metrics.completeness[$f] // "unavailable") == "unavailable")) | length)}}) | from_entries),
      per_task: (group_by(.task.id) | map({key: .[0].task.id, value: {runs: length, successes: (map(select(.success)) | length), tokens_median: (metric(.metrics.tokens.total).median), failures: (map(select(.success | not) | .failure_category) | map(select(. != null)) | unique)}}) | from_entries),
      requirements: ([.[] | .evaluation.hidden.requirements // {} | to_entries[]] | group_by(.key) | map({key: .[0].key, value: {pass: (map(select(.value == "pass")) | length), total: length}}) | from_entries)
    };

def partition:
  . as $runs
  | ($runs | map(.strategy.name) | unique) as $names
  | ($names | map(. as $s | {key: $s, value: ($runs | map(select(.strategy.name == $s)) | group_stats)}) | from_entries) as $by
  | ($by.baseline // null) as $base
  | {
      runs: ($runs | length), strategies: $by,
      comparison_vs_baseline: (if $base == null then null else
        [$names[] | select(. != "baseline") | . as $s
         | ($runs | map(select(.strategy.name == $s)) ) as $mine
         | ($mine | map(.task.id) | unique) as $tasks
         | ($runs | map(select(.strategy.name == "baseline" and (.task.id as $t | $tasks | index($t) != null)))) as $theirs
         | ($mine | group_stats) as $a | ($theirs | group_stats) as $b
         | {strategy: $s, paired_tasks: ($tasks | length), baseline_runs: $b.runs, runs: $a.runs,
            success_rate: $a.success_rate, baseline_success_rate: $b.success_rate,
            success_delta_pp: (if $a.success_rate == null or $b.success_rate == null then null else (($a.success_rate - $b.success_rate) * 100 | r2) end),
            tokens_median_ratio: (if $a.tokens_total.complete and $b.tokens_total.complete and ($b.tokens_total.median // 0) > 0 then ($a.tokens_total.median / $b.tokens_total.median | r2) else null end),
            tokens_ratio_note: (if ($a.tokens_total.complete and $b.tokens_total.complete) then null else "tokens unavailable for some runs: no ratio" end),
            flags: [ (if $a.success_rate != null and $b.success_rate != null and $a.success_rate < $b.success_rate then "LESS CORRECT than baseline: any token saving is not an improvement" else empty end),
                     (if $a.tokens_total.complete and $b.tokens_total.complete and ($b.tokens_total.median // 0) > 0 and $a.tokens_total.median < $b.tokens_total.median and $a.success_rate != null and $b.success_rate != null and $a.success_rate < $b.success_rate then "cheaper but less correct" else empty end),
                     (if ($a.runs < $min_n or $b.runs < $min_n) then "small sample (n<\($min_n)): differences are anecdotal" else empty end) ] }] end)
    };

(map(select(.simulated | not))) as $real | (map(select(.simulated))) as $sim
| {
    schema: "tbench-report/1",
    runs_total: length, min_n: $min_n,
    integrity: $integrity,
    real: (if ($real | length) > 0 then ($real | partition) else null end),
    simulated: (if ($sim | length) > 0 then ($sim | partition) else null end),
    conclusions_allowed: (($real | length) > 0),
    environment_variants: ($real | map(.environment.os + "/" + .environment.arch) | unique),
    models: ($real | map(.metrics.model) | unique),
    notice: (if ($real | length) == 0 then "NO REAL MODEL MEASUREMENTS: every figure below is simulated fixture data. It validates the harness only and must not be used for cost or quality conclusions." else null end)
  }
