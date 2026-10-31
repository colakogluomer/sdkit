# Project profile: __PROJECT_NAME__

Project facts consumed by the generic spec-driven skills and agents. Machine-readable values live in `sdkit.env`;
this file holds the prose and rubrics. Fill in every section; `scaffold-doctor` fails while a `TODO` remains.

## Tracker
- Which tracker, which tool or MCP fetches a ticket, ticket ID format (or "none": tasks are described in free text).

## Branches and PRs
- Integration branch: see `BASE_BRANCH` in `sdkit.env`. Branch naming and commit format: `rules/git.md`.
- PR tooling (the agent opens the PR itself): TODO e.g. `open-pr.sh` (Bitbucket, GitHub through `gh`, GitLab through `glab`; `PR_HOST` in sdkit.env).
- Commit scopes: TODO list the short names used in `feat(<scope>): ...`.

## Release flow (optional)
- Describe the release-branch flow if there is one, and set `BASE_BRANCH_MODE=release` in `sdkit.env`; otherwise delete this section.

## Verification
- The verify command is `VERIFY_CMD` (empty = the stack engine for `STACK` in `sdkit.env`). Project checks are executable files in `__KIT_DIR__/verify.d/`.

## Test layout
- Unit tests: TODO
- Integration tests (real infrastructure): TODO
- Conventions: the stack rules copied into `rules/` (for example `go-testing.md`, `spring-testing.md`, `react-testing.md`, `rn-testing.md`).

## Protected code
- Paths listed in `PROTECTED_PATHS` and the rule for when they may be changed.

## Risk rubric
Fixed rubric used by `spec-driven-dev` intake. Replace the placeholder criteria with this project's own.

| Label | Criteria |
|---|---|
| `high` | TODO e.g. concurrency or locks, money or billing, auth, destructive migrations, cross-service event ordering |
| `medium` | TODO e.g. a new or changed state-mutating endpoint, a business-rule change, an additive migration |
| `low` | TODO e.g. read-only changes, docs/config/tooling, pure refactors |

## Known pitfalls
See `known-pitfalls.md`. The verifier scans every diff against it.
