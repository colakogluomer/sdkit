# Plan gate (runs before `openspec-propose`)

Purpose: the user sees and edits everything that is about to be written into the proposal, while changing it is still cheap.
Nothing is proposed until the user approves the whole plan. The plan lives in `<project-dir>/work/<slug>/plan.md` (personal, gitignored);
`openspec-propose` receives it as input and `proposal.md` must match it.

## Inputs
The confirmed task brief and risk label (from the `analyst`), the explore findings, and for `medium`/`high` the `engineer`'s draft
design, test strategy and task split. For `low` the orchestrator drafts all of it inline (no engineer run).

## plan.md sections
1. **Scope**: goal, in scope, explicit non-goals.
2. **Assumptions and open questions**: each with the default and what breaks if wrong.
3. **Definition of Done**: one line per item, `D<n>: <testable condition> | Verified by: <unit test|integration test|manual check|none: reason>` (see `rules/test-first.md`). The `D<n>` ids are what `check-plan-parity.sh` compares.
4. **Design**: chosen approach; rejected alternatives in one line each; ADR needed? `high`: the race/ordering scenario.
5. **Execution plan**: tasks with `writes:` / `after:` / `role:` / `size:` (format in `parallel.md`; sizing in `model-routing.md`, read it now), the waves, which tasks run in parallel and why or why not, and which roles are spawned.
6. **Cost shape**: size (S/M/L), number of agent runs by tier (from the task sizes), what is skipped for this risk label. No invented token numbers.
7. **Risks and rollout**: what could go wrong, release constraints, what the user must do after merge.
8. **Decision log**: every change the user makes at this gate, one line each.

## Asking (detailed, but batched)
Use the host's question tool (`AskUserQuestion` in Claude Code, a plain numbered question elsewhere). At most 4 questions per round. Each
question quotes the section text it is about, offers `Approve` / concrete alternatives, and the user can always answer free-form.
Never ask what the code or the task already answers; put a recommended option first.

Rounds, by risk label:

| Risk | Rounds |
|---|---|
| `low` | One round: sections 1, 3 and 5 together, then the final confirmation |
| `medium` | A: 1+2 · B: 3 (DoD and test strategy, item by item) · C: 5+6 · final confirmation |
| `high` | A: 1+2 · B: 3 · C: 4 (design, race scenario) · D: 5+6 · E: 7 · final confirmation |

## Updating
- After every answer, apply it to `plan.md` and log it in section 8.
- **Propagate**: a change to the DoD re-checks the test strategy and the task split; a change to the design re-checks the DoD and tasks; a scope change re-checks everything. Tell the user which sections you adjusted as a consequence and re-ask only if the consequence is not obvious.
- Show only the changed and consequence sections again, not the whole plan.
- The user may say "update the plan" at any later point (during implementation or verification). Re-run only the affected rounds, then update `proposal.md`/`tasks.md` through the OpenSpec skills instead of editing around them.

## Final confirmation
Show the compact summary: scope in one line, DoD list with Verified-by, task waves, roles, risks. Ask exactly:
`Approve and propose` / `Edit a section` (name it) / `Stop here`. Only `Approve and propose` continues to `openspec-propose`.

## After propose
Run `<kit>/scripts/check-plan-parity.sh plan.md proposal.md tasks.md`: it compares the DoD (id, text, Verified-by) with plan section 3 and the tasks with section 5. Report any difference to the user and fix it or update the plan; never leave them silently different.
