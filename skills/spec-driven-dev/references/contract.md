# Agent contract (v1)

Read this only when `CONTRACTS=1` (or a handoff carries `CONTRACT:`). A contract makes a handoff and an answer machine-checkable by `scripts/contract.sh`, with no extra agent and no model call.
**A valid contract only says the exchange is well-formed.** It is not a test result, not a verification and not a phase transition: the verdict stays with the verifier (`parse-verdict.sh`) and the phase with `sdd.sh`.

## Handoff: three extra lines
```
CONTRACT: 1                       (fixed, near the top, keeps the cache prefix)
...the usual handoff lines (handoff.md)...
ID: <task-slug>/<label>           (per spawn; unique in the task: dev-a, verify, verify-2)
REPLY-END: one line "HANDOFF-RESULT/1 | id: <ID> | role: <ROLE> | status: done|partial|blocked|failed | artifacts: <paths|none> | blockers: <text|none> | next: <text|->"
RETRY-OF: <id>                    (only on a retry of an invalid or interrupted id)
```
The existing lines are the rest of the invocation contract: `ROLE` (identity of the role), `TASK` (objective), `READ` (inputs: existing repo-relative paths, comma separated, no prose), `SCOPE: writes:` (allowed scope: path prefixes, or `none` for read-only roles), `OUT` (under `work/<task>/out/`), `DONE WHEN` / `NOT YOUR JOB` (constraints). Nothing is repeated that the orchestrator already holds: no spec text, no git state, no phase.

## Answer: one line at the end
`HANDOFF-RESULT/1 | id: t1/dev-a | role: developer | status: done | artifacts: src/a.sh | blockers: none | next: -`
Fields are fixed: `id role status artifacts blockers next` (`next` optional). `|` and newlines never appear inside a value; `blockers` and `next` are at most 200 characters (the long form goes to `OUT`).
`status`: `done` (blockers `none`), `partial` / `blocked` / `failed` (blockers say why). `artifacts`: files the role wrote, inside `writes:`; read-only roles say `none`.
The role's own format (the verifier's `DOD / FINDINGS / VERIFY / VERDICT`, a design, a findings list) stays as it is; the line only follows it.

## Using it
- Claude Code: the `check-contract` hook validates and registers a contracted spawn (`PreToolUse` on `Agent`) and checks the answer (`SubagentStop`). Neither blocks; an invalid handoff asks first in `strict` mode.
- Other hosts: `run-role.sh` does both when the handoff has a `CONTRACT:` line. Exit 4 = the answer broke the contract, 5 = valid but `partial|blocked|failed`. Otherwise by hand: `contract.sh issue FILE` before, `contract.sh check-result - --id ID --role R --record` after.
- Invalid or interrupted: one retry, as for a malformed verdict: `state.sh <slug> retry <id>`, then a new handoff with a new `ID:` and `RETRY-OF:`. A second failure goes to the user.
- `blocked` / `failed` / `partial` are real answers, not contract errors: read the blockers, decide, do not retry blindly.
- `contract.sh pending` lists handoffs nobody answered (interrupted agent); `contract.sh close <id>` marks one dead.
- Reasons you may see: `no-result malformed unsupported-version missing-field bad-value inconsistent id-mismatch role-mismatch task-mismatch unknown-id duplicate stale unsafe-path missing-artifact out-of-scope`.
