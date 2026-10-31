---
name: incident-to-rule
description: Turn a resolved bug or incident into a lasting guard. Use right after fixing a production bug, a failed verification, or a surprising regression, so the same class of mistake is caught automatically next time.
license: MIT
metadata:
  author: spec-driven-kit
  version: "1.0"
---

A fix that only lives in a commit message will be repeated. This skill turns each incident into the cheapest automatic check that would have caught it.

Read `<project-dir>/known-pitfalls.md` and `<project-dir>/sdkit.env` first.

## 1. Describe the bug class, not the bug
Write one sentence each:
- **Symptom**: what was observed.
- **Root cause**: the general mechanism, stripped of this incident's specifics.
- **Spot it**: what the offending pattern looks like in a diff.

If you cannot state the root cause as a general mechanism, stop. The incident is not understood yet.

## 2. Pick the strongest guard that fits (first match wins)
1. **Lint rule**: can a linter flag the pattern? Add or enable it in the lint config (`LINT_CONFIG` in `sdkit.env`, by default `<project-dir>/golangci.yml`).
2. **Verify policy**: can a grep or diff pattern flag it? Add an executable file to `<project-dir>/verify.d/` (it prints `FAIL: ...` or `WARN: ...` lines; see the existing ones for the protocol).
3. **Regression test**: can a test fail on the bug? Add it next to the code, named per `rules/testing.md`.
4. **Hook**: must a tool call be blocked or confirmed before it happens? Add a script in the host's hook folder (for Claude: `.claude/hooks/`) and wire it in the host's settings (for Claude: `.claude/settings.json`); a hook is host-specific, so it is the one thing that lives outside `.sdkit/`. Record the lesson itself in `<project-dir>/known-pitfalls.md`.
5. **Pitfall entry**: only if none of the above is feasible, add an entry to `<project-dir>/known-pitfalls.md` (symptom, root cause, incident, spot-it). The verifier scans every diff against this file.

Prefer a mechanical guard over prose. Prose is the fallback.

## 3. Record the decision
If the incident forced a design choice (not just a fix), add `<project-dir>/adr/NNNN-<slug>.md` from `<project-dir>/adr/TEMPLATE.md`.

## 4. Confirm the guard works
Reproduce the original bug in a scratch diff and show the new guard failing on it, then passing on the fix. A guard that was never seen failing is not trusted.
