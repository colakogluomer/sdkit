# Git Style Guide

## Commit Messages

Format: `<type>(<scope>): <short description>`

| Type        | When to use                                   |
|-------------|-----------------------------------------------|
| `feat`      | New endpoint, new domain feature              |
| `fix`       | Bug fix in existing behaviour                 |
| `refactor`  | Code restructuring without behaviour change   |
| `test`      | Adding or updating tests only                 |
| `docs`      | OpenAPI, README updates only               |
| `chore`     | Build, tooling, dependency changes            |
| `migration` | SQL migration files added                     |

Scope = short name of the service or module changed (see `<project-dir>/project.md`)

Examples:
```
feat(orders): add GET /api/v1/orders endpoint
fix(billing): return ErrNotFound on missing invoice instead of 500
refactor(admin): extract parseQueryParams helper
test(importer): add table-driven tests for invoice import handler
migration(billing): add index on invoices.customer_id
docs(orders): update openapi.yml for order endpoints
```

Rules:
- Subject line <= 72 characters
- Use imperative mood: "add", "fix", "extract" — NOT "added", "fixes"
- Body (optional): explain **why**, not what. Wrap at 80 chars.
- Do NOT reference implementation details ("changed line 42")

---

## Branch Naming

Pattern: `<type>/<short-description>`

```
feat/orders-list-endpoint
fix/billing-invoice-not-found
refactor/admin-client-layer
test/importer-invoice-import
```

Rules:
- Lowercase, hyphen-separated
- Feature branches off the base branch (`BASE_BRANCH` in `<project-dir>/sdkit.env`); delete after merge

---

## What NOT to Commit

Never commit:
- `.env` files, credentials, tokens, secrets of any kind
- AWS keys, Keycloak secrets, DB passwords
- Binary files, compiled artifacts (`*.exe`, `*.out`)
- `log.Printf` / `fmt.Println` debug statements
- Commented-out code blocks left "for reference"
- Auto-generated temp files not managed by the project
- `TODO` placeholders without a task reference

---

## PR / MR Guidelines

- One logical change per PR — do not bundle unrelated fixes
- PR description must state: **what changed**, **why**, **how to test**
- If an OpenAPI doc changed: mention it explicitly
- If a migration is included: call it out; note if it is destructive
- Keep PRs small: aim for < 400 lines changed; split larger work into stacked PRs

---

## Rebase vs Merge

- Feature branches: **rebase** onto the base branch before merging (clean linear history)
- Do NOT `git push --force` on shared branches
- Squash noisy "wip" / "fix typo" commits before merging
- Merge commits are acceptable on the base branch for PR merges
