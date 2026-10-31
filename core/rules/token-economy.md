# Token economy

Spend tokens where judgement is needed; not on searching, retyping or re-reading.

1. **Right-size the role.** Lookups go to `scout` (light tier), planning checks to `analyst`, design and `high`-risk verification to the strong tier, everything else standard. Roles declare a tier, never a model name (`core/tiers.env`).
2. **Cheap deterministic checks first.** Run the verify command before any LLM review. If it is red, fix that before spending a review.
3. **Hand over artifacts, not conversation.** Spawned roles get a handoff brief with paths (`spec-driven-dev` `references/handoff.md`). Independent roles never get the implementer's reasoning, which also keeps their context small.
4. **Trim output.** Keep only a command's summary line and the failing lines (`| tail -40`); ask roles for a structured block plus at most 15 lines; do not paste whole files or logs into the conversation.
5. **Read narrowly.** Grep for the symbol, open the lines you need; read a whole file only when you will change most of it.
6. **Load on demand.** Read a skill's `references/` file only at the step that needs it.
7. **Depth follows risk.** The analyst always runs at intake (it proposes the risk label, so the label cannot skip it). `low` then skips the engineer run, the independent verifier and parallel waves. Do not add steps a label does not require.
8. **Parallel only when it pays.** Concurrent roles multiply cost; use them for disjoint write sets or read-only reviews (`references/parallel.md`), at most 3 at a time.
9. **One retry, then ask.** A second automatic retry on the same failure burns tokens and rarely helps.
10. **Do not re-derive.** Decisions in `plan.md`'s decision log and results already established in the session are not redone or re-asked.
11. **Spawn only when it pays.** One or two files, or work that needs the conversation you hold, is done in place; roles never spawn roles (`references/delegation.md`).
12. **Keep results short and filed.** A role returns at most 15 lines plus its block; the long form goes to `work/<slug>/out/` and is read only when needed. Ask lookups once, and reuse cached answers (`scripts/lookup-cache.sh`).
13. **Stay inside the budget, and measure it.** Where `MAX_SPAWNS` or `TOKEN_BUDGET_TASK` is set, stop and ask when it is reached; do not shrink verification to fit. `usage.sh report` shows tokens and the cache hit rate.
14. **Keep the prefix stable.** Fixed handoff lines first, per-spawn lines last; the same model within a wave; do not edit standing files mid-task. That is what lets the prompt cache work.
15. **Checkpoint at step boundaries** (`state.sh set step`, `notes.md`) so a clear or compaction costs nothing.
