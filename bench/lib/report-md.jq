# report.json -> Markdown (jq -r -f). Unknowns print as "n/a", never 0.
def f: if . == null then "n/a" else tostring end;
def pct: if . == null then "n/a" else ((. * 1000 | round) / 10 | tostring) + "%" end;
def mm($m): if $m.known == 0 then "n/a (0/\($m.runs) runs have it)" else "\($m.median | f)\(if $m.complete then "" else " (median of \($m.known)/\($m.runs) runs)" end)" end;
def cps($c): if $c.value == null then "n/a (\($c.reason))" else ($c.value | tostring) end;
def cats($o): if ($o | length) == 0 then "-" else ($o | to_entries | map("\(.key)=\(.value)") | join(", ")) end;
def section($title; $p):
  "## \($title)", "",
  "| strategy | runs | success | success rate | failures | tokens (median, all runs) | tokens (median, successful) | duration s (median) | retries (sum) | agent calls (sum) | LLM calls (sum) |",
  "|---|---|---|---|---|---|---|---|---|---|---|",
  ($p.strategies | to_entries[] | .key as $k | .value as $s
   | "| \($k) | \($s.runs) | \($s.successes) | \($s.success_rate | pct) | \(cats($s.failure_categories)) | \(mm($s.tokens_total)) | \(mm($s.tokens_total_successful_runs)) | \($s.duration_s.median | f) | \(if $s.retries.complete then ($s.retries.sum | f) else "n/a (\($s.retries.known)/\($s.retries.runs) known)" end) | \(if $s.agent_calls.complete then ($s.agent_calls.sum | f) else "n/a (\($s.agent_calls.known)/\($s.agent_calls.runs) known)" end) | \(if $s.llm_calls.complete then ($s.llm_calls.sum | f) else "n/a (\($s.llm_calls.known)/\($s.llm_calls.runs) known)" end) |"),
  "",
  "### Cost per successful task (all runs, failed ones included, divided by successes)", "",
  "| strategy | tokens | provider USD (metered) | estimated API-equivalent USD |", "|---|---|---|---|",
  ($p.strategies | to_entries[] | "| \(.key) | \(cps(.value.cost_per_success.tokens)) | \(cps(.value.cost_per_success.provider_usd)) | \(cps(.value.cost_per_success.estimated_usd)) |"),
  "",
  "### Per task (successes/runs, median tokens)", "",
  (($p.strategies | keys) as $ks | ("| task | " + ($ks | join(" | ")) + " |"), ("|---|" + ($ks | map("---") | join("|")) + "|"),
   ([$p.strategies[].per_task | keys[]] | unique[] | . as $t
    | "| \($t) | " + ($ks | map(. as $k | ($p.strategies[$k].per_task[$t] // null) | if . == null then "-" else "\(.successes)/\(.runs), \(.tokens_median | f)\(if (.failures | length) > 0 then " [" + (.failures | join(",")) + "]" else "" end)" end) | join(" | ")) + " |")),
  "",
  "### Data completeness (runs with the metric measured / estimated / unavailable)", "",
  "| strategy | tokens | provider cost | estimated cost | LLM calls | agent calls | retries | phases | roles |", "|---|---|---|---|---|---|---|---|---|",
  ($p.strategies | to_entries[] | .key as $k | .value.completeness as $c
   | "| \($k) | " + (["tokens", "cost_provider", "cost_estimated", "llm_calls", "agent_calls", "retries", "phases", "roles"] | map("\($c[.].measured)/\($c[.].estimated)/\($c[.].unavailable)") | join(" | ")) + " |"),
  "",
  (if $p.comparison_vs_baseline == null then "No baseline runs: no comparison."
   else "### Comparison with baseline (same tasks only)", "",
     "| strategy | paired tasks | runs | success rate | baseline success rate | delta (pp) | median token ratio | flags |", "|---|---|---|---|---|---|---|---|",
     ($p.comparison_vs_baseline[] | "| \(.strategy) | \(.paired_tasks) | \(.runs) vs \(.baseline_runs) | \(.success_rate | pct) | \(.baseline_success_rate | pct) | \(.success_delta_pp | f) | \(.tokens_median_ratio | f)\(if .tokens_ratio_note then " (" + .tokens_ratio_note + ")" else "" end) | \(.flags | join("; ")) |") end),
  "";
"# SDKit task benchmark report", "",
(if .notice then "> **SIMULATED / NO REAL MEASUREMENTS.** \(.notice)", "" else empty end),
"Runs: \(.runs_total). Minimum sample for per-success figures: n >= \(.min_n). Strategies are never ranked here: read correctness first, then cost.", "",
(if (.integrity.tampered | length) > 0 or (.integrity.incomplete | length) > 0 then
  "## Integrity", "",
  "- Runs excluded because their sealed result changed after writing: \(.integrity.tampered | length) \(.integrity.tampered | join(", "))",
  "- Runs that never completed (interrupted or crashed, no result): \(.integrity.incomplete | length) \(.integrity.incomplete | join(", "))", "" else empty end),
(if .real then section("Real runs"; .real) else "## Real runs", "", "None.", "" end),
(if .simulated then section("Simulated runs (harness validation only, fixture data, excluded from conclusions)"; .simulated) else empty end),
"## Measurement limitations", "",
"- Token counts are reported by the host CLI when it prints usage (see docs/design-benchmark.md for the per-host table); hosts that print none leave null, never 0.",
"- Totals marked as medians of k/n runs, or n/a, are incomplete; sums are shown only when every run has the metric.",
"- Provider cost (metered spend) and estimated API-equivalent cost are different columns. Subscription use has no metered spend.",
"- Success = hidden acceptance tests pass AND the pristine public tests still pass AND the agent finished without timeout, crash or output flood. Hidden tests are deterministic but finite: passing them is evidence, not proof.",
"- Success rates with few runs are anecdotal. No confidence intervals are computed at this sample size.",
"- Latency is wall-clock of the agent process on one machine and varies with load and provider.",
"- Local isolation: a git worktree or temp directory is not a sandbox. Hidden-test secrecy holds only when the run used an isolation mechanism that passed `tbench.sh preflight`."
