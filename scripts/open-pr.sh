#!/usr/bin/env bash
# Open a pull request for the current branch. Host comes from PR_HOST in <project-dir>/sdkit.env (default: bitbucket).
# Usage: open-pr.sh "<title>" <description-file> [destination-branch]   (destination defaults to BASE_BRANCH)
# Bitbucket basic auth needs the account EMAIL (BITBUCKET_EMAIL, else git config user.email); the token is read from
# the git remote URL and never printed. Other hosts: see the kit's docs/hosts.md.
set -eu
# The PR is opened against the repo of the current directory. The token comes from that repo's origin URL; if the URL
# carries no credentials (credential-helper setups, sibling repos such as gitops), set PR_TOKEN_REPO in sdkit.env to a
# local repo whose origin URL does, or export BITBUCKET_TOKEN.
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$ROOT"; export KIT_DIR
TOKEN_REMOTE="$(git -C "${PR_TOKEN_REPO:-$ROOT}" remote get-url origin)"
PR_HOST="${PR_HOST:-bitbucket}"
if [ "$PR_HOST" != bitbucket ]; then
  echo "PR_HOST=$PR_HOST is not implemented. Open the PR by hand (github: gh pr create, gitlab: glab mr create)." >&2
  exit 2
fi
ACCOUNT_EMAIL="${BITBUCKET_EMAIL:-$(git config user.email || true)}"
[ -n "$ACCOUNT_EMAIL" ] || { echo "set BITBUCKET_EMAIL or git config user.email (the Bitbucket account email)" >&2; exit 2; }
TITLE="${1:?title}"; DESCRIPTION_FILE="${2:?description file}"; DEST="${3:-${BASE_BRANCH:-develop}}"
SOURCE="$(git rev-parse --abbrev-ref HEAD)"
git rev-parse --verify -q "origin/$SOURCE" >/dev/null || { echo "push $SOURCE first (git push -u origin $SOURCE)"; exit 1; }

REMOTE="$(git remote get-url origin)"
PR_TOKEN="${BITBUCKET_TOKEN:-}" PR_EMAIL="$ACCOUNT_EMAIL" PR_REMOTE="$REMOTE" PR_TOKEN_REMOTE="$TOKEN_REMOTE" PR_TITLE="$TITLE" PR_SOURCE="$SOURCE" \
PR_DEST="$DEST" PR_DESC="$DESCRIPTION_FILE" python3 -I - <<'PY'
import base64, json, os, re, urllib.error, urllib.request
remote = os.environ["PR_REMOTE"]
creds = re.match(r"https://([^@/]+:[^@/]+)@bitbucket\.org/", os.environ["PR_TOKEN_REMOTE"])
if not creds and not os.environ.get("PR_TOKEN"):
    raise SystemExit("no token: the origin URL carries none; set BITBUCKET_TOKEN or PR_TOKEN_REPO (see the script header)")
repo_match = re.match(r"https://(?:[^@/]+@)?bitbucket\.org/([^/]+/[^/]+?)(?:\.git)?$", remote)
if not repo_match:
    raise SystemExit("origin is not a Bitbucket URL")
token = os.environ.get("PR_TOKEN") or creds.group(1).split(":", 1)[1]
repo = repo_match.group(1)
auth = base64.b64encode(f"{os.environ['PR_EMAIL']}:{token}".encode()).decode()
body = {
    "title": os.environ["PR_TITLE"],
    "source": {"branch": {"name": os.environ["PR_SOURCE"]}},
    "destination": {"branch": {"name": os.environ["PR_DEST"]}},
    "close_source_branch": True,
    "description": open(os.environ["PR_DESC"]).read(),
}
request = urllib.request.Request(
    f"https://api.bitbucket.org/2.0/repositories/{repo}/pullrequests", data=json.dumps(body).encode(), method="POST",
    headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(request) as response:
        pr = json.load(response)
        print(f"PR #{pr['id']} {pr['state']} -> {pr['destination']['branch']['name']}: {pr['links']['html']['href']}")
except urllib.error.HTTPError as err:
    hint = " (check that BITBUCKET_EMAIL is the Bitbucket account email)" if err.code == 401 else ""
    raise SystemExit(f"HTTP {err.code}: {err.read().decode()[:300]}{hint}")
PY
