#!/usr/bin/env bash
# Print the Homebrew formula for this kit version. It is committed in this repo as Formula/sdkit.rb: this repository is the tap.
# `using: :git` is required: brew does not recognise ssh (git@host:path) or file:// URLs as git repositories and would download them as a file.
# Usage: gen-formula.sh [--write] [--repo-url URL] [--head-only]
#   --write      write Formula/sdkit.rb in this repo instead of printing
#   default      stable release: needs the git tag v<version> (version = .claude-plugin/plugin.json); pins tag + revision
#   --head-only  no stable block, for trying a branch (brew install --HEAD)
#   --head-branch B  branch that `brew install --HEAD` builds (default master)
#   --repo-url   where brew clones from (default: the SSH URL of this repo's origin; the repo is private, so brew needs your SSH key)
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(jq -r .version "$root/.claude-plugin/plugin.json")"
url="$(git -C "$root" remote get-url origin)"
head_only=0
write=0
branch=master
while [ $# -gt 0 ]; do case "$1" in --repo-url) url="$2"; shift ;; --head-only) head_only=1 ;; --write) write=1 ;; --head-branch) branch="$2"; shift ;; *) echo "unknown option $1" >&2; exit 2 ;; esac; shift; done
# a URL with credentials in it must never end up in a public formula
case "$url" in *://*@*) url="$(printf '%s' "$url" | sed -E 's#(https?://)[^@/]+@#\1#')" ;; esac

# a web address for the homepage field (the clone URL may be ssh)
home="$(printf '%s' "${url%.git}" | sed -E 's#^git@([^:]+):#https://\1/#; s#^ssh://git@([^/]+)/#https://\1/#')"
stable=""
if [ "$head_only" = 0 ]; then
  rev="$(git -C "$root" rev-parse --verify -q "v$version^{commit}")" || { echo "tag v$version does not exist: tag the release commit first (git tag v$version <commit>)" >&2; exit 1; }
  stable="  url \"$url\", using: :git, tag: \"v$version\", revision: \"$rev\"
  version \"$version\"
"
fi

out() { if [ "$write" = 1 ]; then mkdir -p "$root/Formula" && cat > "$root/Formula/sdkit.rb" && echo "wrote Formula/sdkit.rb" >&2; else cat; fi; }
out <<RUBY
class Sdkit < Formula
  desc "Spec-driven development workflow and guards for AI coding agents (Claude Code, Codex, OpenCode, Cursor, Gemini)"
  homepage "$home"
${stable}  head "$url", using: :git, branch: "$branch"

  depends_on "jq"
  depends_on "node" # the OpenSpec CLI (npm) that the workflow drives

  def install
    # the whole kit stays together: scripts find their siblings relative to themselves
    libexec.install Dir["*", ".claude-plugin"]
    bin.install_symlink libexec/"bin/sdkit"
  end

  def caveats
    <<~EOS
      Set a repo up (once per repo, by one person):
        cd your-repo && sdkit init
      OpenSpec is part of the workflow. If it is not installed yet:
        sdkit init --install-openspec     (runs: npm install -g @fission-ai/openspec)
      Check a repo any time:  sdkit doctor
      Upgrade a repo after "brew upgrade":  sdkit upgrade
    EOS
  end

  test do
    assert_match "sdkit", shell_output("#{bin}/sdkit version")
    assert_match(/^#{Regexp.escape(libexec)}$/, shell_output("#{bin}/sdkit where").strip)
  end
end
RUBY
