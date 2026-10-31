Spec-driven development with spec-driven-kit: a map; details live in the linked files.

- Conventions: `__KIT_DIR__/rules/` (incl. `test-first.md`, `token-economy.md`)
- Project facts, release flow, risk rubric: `__KIT_DIR__/project.md`; machine config: `__KIT_DIR__/__KIT_ENV__`
- Verify any change with the spec-driven-kit verify script (`/scaffold-doctor` shows how); project checks live in `__KIT_DIR__/verify.d/`
- Where things live: everything shared is in `__KIT_DIR__/` (committed, including the team's settings in `__KIT_DIR__/__KIT_ENV__`); `__KIT_DIR__/sdkit.local.env` and `__KIT_DIR__/work/` are personal. New project knowledge goes there (`memory.sh add`, `incident-to-rule` for pitfalls, `adr/` for decisions), never into host folders such as `.claude/` or `.codex/`.
- Project memory (only if `MEMORY=1` in `__KIT_DIR__/__KIT_ENV__`): read `__KIT_DIR__/memory/INDEX.md` at the start, open an entry only when its line is relevant. Details: `spec-driven-dev` `references/memory.md`.
- Start new tasks with the `spec-driven-dev` skill (analyst intake, plan gate before any proposal, role-based work). After fixing a bug, use `incident-to-rule`
- Roles: `analyst`, `scout`, `engineer`, `developer`, `test-writer`, `devsecops`, `reviewer`, `security-auditor`, `verifier`; you are the orchestrator
- Past incident classes the verifier checks: `__KIT_DIR__/known-pitfalls.md`; decisions: `__KIT_DIR__/adr/`
