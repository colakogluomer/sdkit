# Security hardening (F19)

The audit separates what the kit **actually enforces** (hook/script code) and counts only what is written in a prompt as "not enforced".

| Area | Enforcement | Where |
|---|---|---|
| Read-only roles | no Edit/Write in the `agents/*.md` tool list + the `guard-readonly.sh` hook | `audit.sh policy` checks both |
| Secrets | `guard-secrets.sh`; `redact.sh` in views (summary/envelope output, error messages, audit values) | full text on disk is **not modified** (evidence integrity) |
| Data egress to a provider | `adapters.d/litellm.sh`: `LITELLM_EGRESS=allow`, host allow-list, text-only (independent and writing roles are refused), key via stdin | the audit record is written **first**: no record, no request |
| Audit trail | `<project-dir>/audit.jsonl`, hash-chained, metadata only (kind, role, host, bytes); no prompt/answer/content, values over 120 characters are rejected | `audit.sh verify` finds edits/deletions in the middle; it **cannot prevent truncating the tail** |
| External adapter | `adapters.d/*.sh` writable permissions and `capabilities` validity | `audit.sh policy` |

`redact.sh` works with known formats (AWS key id, GitHub/Slack tokens, `sk-…`, JWT, Bearer, `password=`, private key blocks). An unknown format passes through: **a filter, not a guarantee**. `check-writes.sh` and `worktree.sh merge` are unchanged for the sandbox/worktree boundary. No critical issue was found in the audit this round; for the path I added myself (the litellm adapter), the key not appearing in `ps` and being masked in error messages is pinned by a test. A live provider and live Claude hook payloads were not tried. `tests/security.test.sh`.
