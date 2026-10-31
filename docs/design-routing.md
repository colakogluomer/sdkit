# Smart orchestration and cost-aware routing (F06)

This document describes `scripts/route.sh` (the decision engine), `core/adapters.json` (the execution contract) and how `scripts/run-role.sh` consumes that decision.
In short: **the core owns policy, adapters declare capabilities, providers execute.** No model is called for any decision.

## 1. What it solves and what it does not

| Question | Answered by | Model call |
|---|---|---|
| Is the next role mandatory? | `workflow.sh policy` (risk + profile); `route.sh` only reads it | none |
| Which adapter and model? | `route.sh` (registry + risk + role + preference) | none |
| Run it, or reuse? | `route.sh` (`sdd.sh evidence` state) | none |
| After a failure: retry / escalate / stop? | `route.sh` (failure class + limits) | none |
| Does the budget allow it? | `route.sh` (usage ledger + settings) | none |

**Mandatory** model calls added: 0. The cost per decision is local processes only (measurement: §10).

Out of scope (deliberately): LiteLLM, FusionCLI or any proxy/gateway; an external orchestration service; a concurrent agent scheduler; F07/F08.

## 2. Architecture

```
                 sdkit.env (ROUTING, ROUTE_*)         core/tiers.env + <project-dir>/models.json  (registry)
                              │                                        │
 workflow.sh policy ──► ┌──────────────┐ ◄── sdd.sh evidence      core/adapters.json (capabilities)
 (risk, profile,        │   route.sh   │ ◄── usage.jsonl (usage)
  mandatory roles)      │   decide     │ ◄── work/<task>/routing.jsonl (previous attempts)
                        └──────┬───────┘
                               │ decision (JSON): action, adapter, model, tier, budget, attempt, reason, policy_version
                               ▼
                        run-role.sh ──► host CLI (claude | codex | opencode | cursor-agent | gemini) ──► provider
                               │ when the process ends
                               ▼
                        route.sh outcome  (failure class, duration, tokens: null if absent)  ──► the next decision reads this
```

With `ROUTING=on`, `run-role.sh` **consumes** the decision: host, model, tier, timeout and wait all come from the decision; a decision other than `execute|retry|escalate`
starts nothing. If `route.sh` is missing or produces no decision, `run-role.sh` **does not run** (exit 2): the policy is never silently skipped.

## 3. Decision lifecycle

`route.sh decide --role R` evaluates the following in order; the first definite answer wins:

1. Settings and registry validation (`CONFIG_INVALID`), role text (`UNKNOWN_ROLE`).
2. Task facts: risk, profile, whether the role is mandatory (`workflow.sh policy --json`). With no open task, the risk is **assumed to be medium** and no downgrade is applied.
3. **Evidence** (verifier/reviewer/security-auditor only):
   if a BLOCK stands for this diff → `stop` (`SECURITY_BLOCK` / `VERIFICATION_FAILED`); neither `--rerun` nor another provider changes this.
   If the `sdd.sh evidence` state is `valid` → `reuse` (`EVIDENCE_REUSED`). If it is `stale|untrusted|conflict|missing`, run.
4. **Chain** (same role + same handoff + same diff where relevant = same request): if a run is in flight, `DUPLICATE_IN_FLIGHT`; an identical completed request gives `DUPLICATE_COMPLETED`
   (overridden with `--rerun <reason>`); depending on the previous failure class, `retry` / `escalate` / `stop` (§6).
5. **Tier**: the role's own tier → `--tier` (independent roles never go below their own tier) → risk floors (`ROUTE_FLOOR_*`; at high risk the verifier gets the deep tier).
6. **Adapter and model**: candidate adapters (`--host` > preference > fixed policy > `VERIFIER_HOST`/`RUN_ROLE_HOST` + `ROUTE_FALLBACK_HOSTS`); required capabilities; from the registry,
   the lowest-tier entry that supports the role and is **at or above the required tier**. A lower tier is never substituted.
7. **Budget** (§8). If a mandatory role cannot run because of the budget, `BUDGET_EXHAUSTED` (exit 3): the task state does not change, and no fake PASS is written.
8. With `--reserve`, the decision is written to the decision ledger and the call count goes up (under a lock: two concurrent requests cannot start the same run).

Output (abbreviated): `decision_id, task, role, role_class, mandatory, risk, profile, action, adapter, model, effort, tier, tier_enforced, timeout_s, budget, attempt, wait_s, reason, policy_version`
(+ `previous`, `notes`, `warnings` when needed). Every decision carries a single **reason code**.

### Reason codes

| Action | Codes |
|---|---|
| execute | `ROLE_CAPABILITY_MATCH`, `RISK_FLOOR_APPLIED`, `DOWNGRADE_LOW_RISK`, `PREFERENCE_APPLIED`, `OVERRIDE_APPLIED`, `FIXED_POLICY`, `ADAPTER_FALLBACK`, `RERUN_REQUESTED` |
| reuse | `EVIDENCE_REUSED` |
| retry | `RETRY_TRANSIENT`, `RETRY_RATE_LIMIT`, `RETRY_TIMEOUT`, `RETRY_INTERRUPTED`, `RETRY_INVALID_OUTPUT`, `RETRY_CONTRACT_FAILURE`, `ADAPTER_FALLBACK` |
| escalate | `ESCALATE_INVALID_OUTPUT`, `ESCALATE_CONTRACT_FAILURE` |
| stop (exit 3) | `BUDGET_EXHAUSTED` |
| stop (exit 2, policy/configuration refusal) | `CONFIG_INVALID`, `UNKNOWN_ROLE`, `NO_ADAPTER`, `ADAPTER_UNSUPPORTED`, `NO_COMPATIBLE_MODEL`, `OVERRIDE_INVALID`, `OVERRIDE_BELOW_FLOOR`, `PREFERENCE_INVALID`, `PREFERENCE_BELOW_FLOOR`, `FIXED_INVALID`, `FIXED_BELOW_FLOOR`, `NO_ESCALATION_TARGET` |
| stop (exit 7, not run) | `SECURITY_BLOCK`, `VERIFICATION_FAILED`, `DUPLICATE_IN_FLIGHT`, `DUPLICATE_COMPLETED`, `RETRIES_EXHAUSTED`, `ESCALATION_LIMIT`, `REPORTED_FAILURE`, `UNCLASSIFIED_FAILURE`, `OPTIONAL_SKIPPED` |

`run-role.sh` exit codes: the host's code | 3 budget | 2 policy/configuration refusal | **7 routing decided not to run** (reuse, duplicate, standing BLOCK, ...).
7 never means "verified"; evidence is read with `sdd.sh evidence`.

## 4. Registry (models)

The default entries are **derived** from `core/tiers.env`; the kit does not invent model names, prices or context limits.

| Field | Meaning |
|---|---|
| `id` | unique ID (`claude:standard`) |
| `adapter` / `provider` | execution adapter / known provider hint (`core/adapters.json`) |
| `model` | the `--model` value; `null` = the host's default model |
| `effort` | codex only: reasoning effort (tiers are told apart by it) |
| `tier` | `light|standard|strong`; `*` = "host default", the tier **cannot be verified** (`tier_enforced:false`, the decision carries a `MODEL_INHERITED` warning) |
| `roles` | `"*"` or a list of roles |
| `status` | `available|disabled` |
| `cost` | only if present in the user's `pricing.json` table; otherwise `null` |
| `usage_accounting` | the adapter's token-reporting capability |
| `context`, `tools` | `null` / `true` if unknown |

Project-specific entries go into `<project-dir>/models.json` (a JSON array); the same `id` **overrides** the derived entry, and a new `id` is added. Example:

```json
[
  {"id": "gem:fast", "adapter": "gemini", "model": "<your-model-id>", "tier": "light", "roles": ["scout", "analyst"]},
  {"id": "claude:strong", "adapter": "claude", "model": "opus", "tier": "strong", "status": "disabled"}
]
```

`route.sh registry` shows the registry; `route.sh validate` checks the settings and `models.json`.

## 5. Execution contract (adapters)

`ExecutionAdapter` is a concept; there is no new framework. Its counterparts: `capabilities()` = `core/adapters.json`, `execute()` = the host branch of `run-role.sh`,
`usage()` = the token parsing in that branch, `cancel()` = **none** (no adapter claims it).

Values: `declared` = the kit uses the flag/output according to the host's documented headless mode, **not verified against a live CLI**; `kit` = the kit provides it; `none` = not supported.
No capability is marked "verified live" (`tests/route.test.sh` checks this, and the `model_selection`/`usage_reporting` claims, against `run-role.sh`'s real command line).

| Capability | claude | codex | opencode | cursor | gemini |
|---|---|---|---|---|---|
| noninteractive, tool_use | declared | declared | declared | declared | declared |
| model_selection | declared | declared (`-m`; also effort for the tier) | declared | declared | declared |
| usage_reporting (tokens) | declared | none | none | none | declared |
| cache usage | declared | none | none | none | none |
| structured_output | declared | none | none | declared | declared |
| cancellation | none | none | none | none | none |
| timeout | kit | kit | kit | kit | kit |
| cost_reporting (actual cost) | none | none | none | none | none |

`timeout` is **hard** only if the machine has `timeout` or `gtimeout`; otherwise the decision marks it `advisory`.
Future adapters (an OpenAI-compatible gateway, LiteLLM, a local model, an enterprise provider) are connected by adding an entry to `adapters.json` and a branch to `run-role.sh`; none was added now.

## 6. Retry and escalation

At the end of every run, `run-role.sh` records the outcome with `route.sh outcome`, **classifying** it; the next request reads this class.

| Class | How it is determined | Next decision |
|---|---|---|
| `OK` | exit 0, not a BLOCK | if the same request comes again, `DUPLICATE_COMPLETED` (for evidence roles, the evidence state decides) |
| `TRANSIENT` | stderr: 502/503/504, connection reset, network ... | `retry` with the same model, at most `ROUTE_MAX_RETRIES` (2) |
| `RATE_LIMIT` | stderr: 429, rate limit, quota, overloaded | `retry` + `wait_s` backoff (`ROUTE_BACKOFF_S` × attempt) |
| `TIMEOUT` | exit 124 or stderr timeout/deadline | `retry` (same limit) |
| `INTERRUPTED` | a decision exists, the process died, no result | `retry` |
| `INVALID_OUTPUT` | exit 6 (no valid verdict block) | one `retry`, then `escalate` (`ROUTE_MAX_ESCALATIONS`, 1) |
| `CONTRACT_FAILURE` | exit 4 | same |
| `HOST_MISSING` | exit 127 | the next adapter in `ROUTE_FALLBACK_HOSTS`, otherwise `stop` |
| `REPORTED_FAILURE` | exit 5 (valid but partial/blocked/failed) | `stop`: this calls for a **code fix** (`state.sh retry`), not an infrastructure retry |
| `VERIFICATION_FAILURE` | verifier/reviewer BLOCK | `stop` |
| `SECURITY_BLOCK` | security-auditor BLOCK | `stop`; changing the provider/model does not turn a BLOCK into a PASS |
| `BUDGET_EXHAUSTED` | exit 3 | the budget is re-evaluated |
| `UNKNOWN` | unexplained failure | `stop` (`UNCLASSIFIED_FAILURE`): no blind retry |

- Infrastructure retries (`ROUTE_MAX_RETRIES`) are **separate** from the code-fix retry (`state.sh retry`, a single chance) and do not consume it.
- The chain total is capped by `ROUTE_MAX_ATTEMPTS` (4). There is no blind repetition of the same handoff: every retry has a reason code and a `previous.failure_class` record.
- Escalation goes one tier up, capped by `ROUTE_ESCALATE_TO` (strong); an attempt that ran with the host's default model (tier cannot be verified) cannot be escalated (`NO_ESCALATION_TARGET`).
- Escalation does not loosen the evidence requirement: the evidence gate and the risk floors apply as is. The full context need not be repeated: the record carries only the decision ID and the failure class.

## 7. Scheduling and independence

- **Mandatory** (`mandatory:true`): verifier, reviewer and security-auditor at high risk; the verifier at medium/high risk or in the `high-assurance` profile. If the budget is not enough, it stops (`BUDGET_EXHAUSTED`); it is not skipped.
- **Optional**: scout, analyst, and reviewer/security-auditor below high risk. When the task token budget reaches the warning level (`TOKEN_BUDGET_WARN_PCT`) they are skipped **with a reason** via `OPTIONAL_SKIPPED` (forced with `--rerun`).
- **Completed**: `reuse` if valid trusted evidence exists; stale evidence is never reused.
- Routing the same model to several roles does not break independence: identity is protected by `run-role.sh`'s process-owned run ID and the per-role registration (F04); role separation is enforced as is.

## 8. Budget semantics: hard or advisory

| Limit | Setting | Class | When |
|---|---|---|---|
| Agent call count | `MAX_SPAWNS` | **hard** | counted before the process starts |
| Attempt count | `ROUTE_MAX_ATTEMPTS`, `ROUTE_MAX_RETRIES`, `ROUTE_MAX_ESCALATIONS` | **hard** | at decision time |
| Task token budget | `TOKEN_BUDGET_TASK` | hard **only** if the usage of every previous run was reported and the adapter reports usage; otherwise **advisory** | a new run does not start when at or over budget; a running process is not killed |
| Role token budget | `ROUTE_ROLE_TOKENS` | same | same |
| Duration | `ROUTE_TIMEOUT_S` | **hard** if `timeout`/`gtimeout` exists, otherwise advisory (recorded) | via the process wrapper |
| Monetary | `ROUTE_BUDGET_COST` | **always advisory**: an **estimate** from the user's `pricing.json` + token usage; no adapter reports actual cost | produces a warning, does not stop |

Accounting rules: a run that reports no usage is **not counted as zero**; it counts as "not measured" (`tq:"unavailable"` in the `usage.jsonl` line, `tokens:null` in the `routing.jsonl` outcome).
If nothing was measured, `used:null`; if some runs were not measured, `accounting:"partial"` and the figure is a lower bound (`USAGE_PARTIAL`). Estimated and actual cost are separate fields (`estimated_usd` / `actual_usd:null`).

When the budget runs out: `BUDGET_EXHAUSTED` (exit 3), the phase/state does not change, no evidence is written. Recovery: raise the limit in `sdkit.local.env` (nothing is lost) or, with user approval, use `--ignore-budget`
(meaningful only with `SDD_MODE=strict`; the decision is recorded with a `BUDGET_OVERRIDDEN` warning). `SDD_MODE=guided` only warns, and `off` does not evaluate the budget at all (same as the old behaviour).

## 9. Settings

All are optional; only `ROUTING=on` is needed. Shared ones go in `sdkit.env`, personal limits in `sdkit.local.env`.

```
ROUTING=on                      # off (default): run-role.sh works as before
ROUTE_POLICY=tiered|fixed       # fixed + ROUTE_FIXED_MODEL=<entry id>: one model for reproducible experiments
ROUTE_DOWNGRADE_LOW=0           # 1: low-risk work roles one tier cheaper (off by default; until the F05 measurement)
ROUTE_FLOOR_LOW/MEDIUM/HIGH     # lowest tier per risk (light, light, standard)
ROUTE_FALLBACK_HOSTS="codex"    # tried in order if the selected host cannot run
ROUTE_MAX_RETRIES=2  ROUTE_MAX_ESCALATIONS=1  ROUTE_ESCALATE_TO=strong  ROUTE_MAX_ATTEMPTS=4  ROUTE_BACKOFF_S=10
ROUTE_PREFER_DEVELOPER=claude:standard      # per-role preference (entry id); must meet the required tier
ROUTE_ROLE_TOKENS=  ROUTE_TIMEOUT_S=  ROUTE_BUDGET_COST=   # personal limits
```

Explicit override: `run-role.sh --model M` accepts only a model that is in the registry, available, and at or above the required tier; otherwise `OVERRIDE_INVALID` / `OVERRIDE_BELOW_FLOOR`.
No override bypasses the risk floor, the evidence rule or a mandatory role.

Inspection (calls no LLM, records nothing):

```
$ route.sh explain --role developer --risk medium
Task: add-retry
Risk: medium (profile standard)
Role: developer (work)
Decision: execute
Adapter: claude
Model: sonnet (tier standard)
Reason: ROLE_CAPABILITY_MATCH
Budget: attempts=hard
Policy: route-v1  Routing: on
```

Other commands: `route.sh decide --json`, `outcome`, `classify`, `registry`, `capabilities`, `validate`, `log`.

## 10. Default routing matrix (no measurement claim)

These are **conservative defaults**, not measured quality/cost results. The model column is for claude through `core/tiers.env`; other hosts follow §4.

| Role (class) | Low risk | Medium risk | High risk | Repeated failure |
|---|---|---|---|---|
| developer, test-writer, devsecops (work) | standard (light with `ROUTE_DOWNGRADE_LOW=1`) | standard | standard (higher with `ROUTE_FLOOR_HIGH`) | one tier up, up to `ROUTE_ESCALATE_TO` |
| engineer, orchestrator (work) | strong | strong | strong | already at the ceiling |
| scout (lookup) | light | light | light | — |
| analyst (lookup) | standard | standard | standard | — |
| verifier (gate) | standard | standard | **strong** (deep tier) | one tier up |
| reviewer, security-auditor (gate) | standard | standard | standard | one tier up |

Gate roles never go below their own tier, under any condition. Downgrading at low risk is off by default: no "savings" are claimed without F05-B results.

**Token impact**: no mandatory model call is added (decisions are pure shell+jq). Real model calls **may go down** (valid evidence is reused, duplicate runs are blocked, no wasted verification on a diff with a BLOCK),
but this is not a measurement. Measured deterministic overhead: one `decide` ~0.4 s wall clock (macOS, ~50 local processes), one stderr line per `run-role.sh`. The figures were measured by hand, not in `tests/route.test.sh`.

## 11. Benchmark compatibility (F05)

- `ROUTING` defaults to `off`; the `bench/` strategies, tasks and baseline results did not change, and historical configurations do **not enable** the new routing.
- Routing is versioned (`policy_version: route-v1`); every decision is stored in `routing.jsonl` and (with TELEMETRY=1) in a `workflow.decision` event (`source=routing`): a run can be reconstructed.
- Fixed-model experiments: `ROUTE_POLICY=fixed` + `ROUTE_FIXED_MODEL` (still does not lower the floors; refused with `FIXED_BELOW_FLOOR` if it is not enough for a gate role).
- A paid benchmark is never run automatically. Downgrade calibration will be done once F05-B results are in.

## 12. Backward compatibility and trust boundaries

Enforced (code refuses/records): decision consumption on the `run-role.sh` path; not running if `route.sh` is missing; the tier floor for gate roles; a BLOCK is not re-judged on the same diff; duplicate/in-flight requests are blocked (under a lock);
spawn and attempt counts; the token limit (if usage is reported); settings and registry validation; validation of explicit model overrides.

Advisory / manual: adapter capabilities (`declared`, not verified live); the token limit if usage is not reported; the money limit; the duration limit if there is no `timeout` command; flows that call the host's native subagents (Codex, OpenCode, Cursor, Gemini) —
these do not use `run-role.sh` and follow routing only by consulting `route.sh explain` by hand. On Claude Code, the PreToolUse(Agent) hook asks for a `route.sh` preview when `ROUTING=on`
(`ask` for reuse/a standing BLOCK/a duplicate/a `model` below the tier floor); if no model parameter is given, the session default is used and cannot be checked.

Accepted limits:
- The chain key is a digest of the handoff text: changing the handoff makes a new request. This prevents accidental loops, not a malicious orchestrator. Gate evidence and a standing BLOCK are tied to the diff fingerprint, not to the handoff.
- At medium and low risk, reviewer/security-auditor answers are free-form and are not recorded as evidence; their BLOCK is not reflected in `outcome` (only at high risk).
- `--ignore-budget` assumes user approval; the code cannot verify it (same as the old behaviour).
- Process liveness is checked with `kill -0`; another user's process looks "dead". Records without a pid are released after `ROUTE_INFLIGHT_TTL_S`.
- No adapter has been verified against a live CLI (the UNVERIFIED note in the `run-role.sh` header applies).
- If the host's default model runs (an empty tier model for cursor/gemini), the tier cannot be verified; the decision says so with `tier_enforced:false`.

## 13. Tests

`tests/route.test.sh` (no model calls; fake CLIs only): configuration and registry, risk/role/capability routing, overrides and preferences, fixed policy, fallback host, mandatory/optional roles, evidence reuse and staleness,
duplicate and concurrent requests, failure classes with retry/escalation limits, the hard/advisory budget split, unmeasured usage, cost estimate, budget recovery, `run-role.sh` integration,
telemetry, the Claude Code hook, the old behaviour when routing is off, benchmark files unchanged.
