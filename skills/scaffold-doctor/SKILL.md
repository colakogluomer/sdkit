---
name: scaffold-doctor
description: Check that this repo's spec-driven-kit setup is complete and say what to fix. Use after scaffold-init, after pulling changes to the project directory, or when a guard or the verify step seems not to run.
license: MIT
metadata:
  author: spec-driven-kit
  version: "2.1"
---

1. Locate the kit: `${CLAUDE_PLUGIN_ROOT}` when set; otherwise ask for the path to the `spec-driven-kit` checkout.
2. Run `"<kit>/bin/doctor.sh" "$PWD"` and show the output.
3. For each `FAIL`, say what to change and in which file. Do not edit `project.md` yourself: the risk rubric is the user's decision.
4. `WARN` lines about a host CLI (`codex`, `opencode`, `cursor-agent`, `gemini`) only matter for `scripts/run-role.sh --host <host>`; mention them, do not treat them as failures.
5. Copy-mode installs and non-Claude hosts: if the kit moved on (a version change: offer `bin/upgrade.sh` first), offer `"<kit>/bin/sync.sh" "$PWD"`; it keeps local edits and prints a diff for conflicts.
