# Pull-request hosts

`scripts/open-pr.sh "<title>" <description-file> [destination-branch]` opens the PR for the current branch (destination defaults to `BASE_BRANCH`). `PR_HOST` in `<project-dir>/sdkit.env` selects the host; an environment variable overrides it. (These are Git hosting services; the agent tools the kit runs on - Claude Code, Codex, OpenCode, Cursor, Gemini CLI - are covered in the README and `docs/guide.md` §16.)

Push the branch first: every host refuses with exit 1 when `origin/<branch>` does not exist. An unknown `PR_HOST` exits with code 2 before touching the network.

| `PR_HOST` | Tool | Setup |
|---|---|---|
| `bitbucket` | Bitbucket REST API (built in) | Auth: `BITBUCKET_EMAIL` (else `git config user.email`) plus an app password. The password is read from the `origin` URL, or from `BITBUCKET_TOKEN`, or from another local repo named in `PR_TOKEN_REPO`. It is never printed. |
| `github` | `gh pr create --base <dest> --head <branch> --title ... --body-file ...` | Install [`gh`](https://cli.github.com) and run `gh auth login` (or export `GH_TOKEN`). GitHub Enterprise: `gh auth login --hostname <host>`. |
| `gitlab` | `glab mr create --source-branch <branch> --target-branch <dest> --title ... --description ... --yes` (source-branch removal follows the project setting) | Install [`glab`](https://gitlab.com/gitlab-org/cli) and run `glab auth login` (or export `GITLAB_TOKEN`). Self-managed: `glab auth login --hostname <host>`. |
| `auto` | one of the above | Picked from the `origin` URL: `github.com` → github, `bitbucket.org` → bitbucket, any `gitlab.*` host → gitlab. For other self-hosted names set `GH_HOST` or `GITLAB_HOST`, or set `PR_HOST` explicitly. New setups get `auto`; the script's own default stays `bitbucket` for existing repos. |

## CI gate

`sdkit init --ci bitbucket|github|gitlab` installs the server-side gate (`sdd.sh ci-check`) as `bitbucket-pipelines.yml`, `.github/workflows/spec-driven-gate.yml` or `.gitlab-ci.yml`. The file is project-owned: an existing one is kept, so merge the job by hand. Make the check required (GitHub: branch protection; Bitbucket: merge checks; GitLab: Settings > Merge requests > "Pipelines must succeed").
