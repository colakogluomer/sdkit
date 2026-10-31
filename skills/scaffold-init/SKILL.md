---
name: scaffold-init
description: Set up a repo for the spec-driven workflow. Writes the project profile to fill in (rules, project.md, sdkit.env, settings), adds files for other hosts when asked, and initializes OpenSpec. Run once per repo by whoever sets it up; developers who clone an already set-up repo do not need it.
license: MIT
metadata:
  author: spec-driven-kit
  version: "2.2"
---

1. Locate the kit: `${CLAUDE_PLUGIN_ROOT}` when set; otherwise ask the user for the path to the `spec-driven-kit` checkout.
2. If `<project-dir>/project.md` already exists, stop and say the repo is set up; offer `scaffold-doctor` instead.
3. Ask which hosts the team uses (any of `claude`, `codex`, `opencode`, `cursor`, `gemini`) and, if the repo is not obviously one stack, which stack (`go`, `spring-boot`, `nextjs`, `react-native`; auto-detected otherwise). Run `"<kit>/bin/init.sh" --host <comma-separated hosts> [--stack <stack>] --mode plugin "$PWD"` (`--mode` only matters for Claude Code) and show its output. It never overwrites an existing file unless `--force` is passed; do not pass `--force` without asking.
4. OpenSpec: if the `openspec` CLI is installed and `openspec/` does not exist, run `openspec init`. If the CLI is missing, tell the user `npm install -g @fission-ai/openspec` and continue.
5. Help fill in `<project-dir>/project.md` with the user (tracker, test layout, commit scopes, protected code, **risk rubric**). The rubric is the user's decision; propose wording but do not invent criteria.
6. Non-Claude hosts: tell the user to run `git config core.hooksPath .githooks` in every clone; for Codex, confirm multi-agent is enabled; for Cursor and Gemini, merge the generated `.cursor/hooks.json` / `.gemini/settings.json` into existing ones.
7. Run the `scaffold-doctor` skill and report what still fails.
