# Handoff brief

What the orchestrator gives a role when it spawns one. Small on purpose: a role that needs more reads the named files itself.
Independent roles (`verifier`, `reviewer`, `security-auditor`) get artifacts only, never the implementer's reasoning or conversation.

```
ROLE: <role>          RISK: low|medium|high      PROJECT-DIR: <.sdkit, or a pre-1.0 .agentkit|.claude|.codex>
TIER: <light|standard|strong>   (from the task's size:, see model-routing.md; omit when the task has no size:)
TASK: <one or two sentences; for a task from tasks.md include its id>
READ: <paths: plan.md / proposal.md / design.md / the files to change or review>
SCOPE: writes: <paths this role may change; none for read-only roles>
WORKTREE: <absolute path from `worktree.sh path <id>`; omit when not working in a task worktree>
DONE WHEN: <the DoD item numbers or tests that must pass / the output format expected>
DIFF-BASE: <ref>      (reviewers and the verifier)
TESTS: <named test files or commands; frozen files are listed in <project-dir>/.frozen>
NOT YOUR JOB: <what to leave to other roles>
OUT: <work/<slug>/out/<role>-<n>.md; where the long form goes; omit for short answers>
```
Optional contract (`CONTRACTS=1`, `references/contract.md`): add `CONTRACT: 1` near the top and, with the per-spawn lines, `ID: <slug>/<label>` and the fixed `REPLY-END:` line. The role then ends its answer with one `HANDOFF-RESULT/1 | ...` line that `contract.sh` checks. Without a `CONTRACT:` line nothing changes.

Rules:
- Order is cache-friendly: the fixed lines (ROLE, RISK, PROJECT-DIR, READ of standing files) come first and the lines that change per spawn (TASK, DIFF-BASE, TESTS) last, so a shared prefix between spawns can be served from the prompt cache.
- `OUT`: a writing role (`engineer`, `developer`, `test-writer`, `devsecops`) puts its long form there and returns a short summary plus the path. A read-only role cannot write files: it keeps its answer short and you store it yourself (`run-role.sh --out`, or write the text to that path). Read the file only when the summary is not enough. The structured block (the verifier's `DOD / FINDINGS / VERIFY / VERDICT`) always stays in the answer.
- `TIER`: the model tier the orchestrator picked for this spawn (`model-routing.md`). On Claude Code it sets the `Agent` call's `model`; elsewhere it is the `--tier` of `run-role.sh`. A role does not act on it itself. Independent roles are never handed a tier below their own.
- `WORKTREE`: the role reads and writes only under that path (absolute paths; never the main checkout). Before merging, the orchestrator runs `check-writes.sh` (`worktree.sh merge` does it) so a stray edit outside `writes:` is caught. A host that cannot pin a subagent's directory runs the role as a separate process: `run-role.sh <role> --handoff <file> --cwd <worktree>`.
- Roles never call other roles. A role that needs a lookup ends its answer with `NEEDS-LOOKUP: <question>` lines; the orchestrator runs `scout` once and hands the answer back as a path.
- Paths, not pasted contents. The role reads what it needs.
- State the output format you want (each role defines its own) and ask for a summary of at most 15 lines plus the structured block.
- Never include: the orchestrator's history, why a previous attempt failed (give the failing items instead), or opinions about the answer.
- On a retry, hand over only the specific failing DoD items or findings.
