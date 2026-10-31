# Pull-request hosts

`scripts/open-pr.sh` opens the PR for the current branch. `PR_HOST` in `<project-dir>/sdkit.env` selects the host. (These are Git hosting services; the agent tools the kit runs on - Claude Code, Codex, OpenCode, Cursor, Gemini CLI - are covered in the README and `docs/guide.md` §16.)

| Host | Status | Setup |
|---|---|---|
| Bitbucket | implemented | Push the branch first. Auth: `BITBUCKET_EMAIL` (else `git config user.email`) plus an app password. The password is read from the `origin` URL, or from `BITBUCKET_TOKEN`, or from another local repo named in `PR_TOKEN_REPO`. It is never printed. |
| GitHub | not implemented | Install `gh`, run `gh auth login`, set `PR_HOST=github` and open PRs with `gh pr create --base <branch> --title ... --body-file ...`. List this command in `project.md` ("PR tooling") so the agent uses it. |
| GitLab | not implemented | Install `glab`, run `glab auth login`, use `glab mr create --target-branch <branch> --title ... --description ...`, and record it in `project.md` the same way. |

For an unimplemented host the script exits with code 2 before touching the network.
