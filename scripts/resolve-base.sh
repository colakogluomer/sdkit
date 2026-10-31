#!/usr/bin/env bash
# Prints the ref a branch should be diffed against and branched from.
#   BASE_BRANCH_MODE=release  newest release branch this HEAD descends from (feature work is cut from the release)
#   otherwise                 origin/$BASE_BRANCH
# VERIFY_BASE in the environment overrides everything. Add --frozen to print "frozen" / "open" for that release.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$PWD"; export KIT_DIR
BASE_BRANCH="${BASE_BRANCH:-develop}"
PREFIX="${RELEASE_BRANCH_PREFIX:-release/}"
FREEZE="${FREEZE_TAG_PREFIX:-freeze/}"

fallback() { git rev-parse --verify -q "origin/$BASE_BRANCH" >/dev/null && echo "origin/$BASE_BRANCH" || echo "$BASE_BRANCH"; }

pick_release() {
  best=""; best_dist=""
  for ref in $(git for-each-ref --format='%(refname:short)' "refs/remotes/origin/${PREFIX}*" | sort -V); do
    fork="$(git merge-base "$ref" HEAD 2>/dev/null)" || continue
    dist="$(git rev-list --count "$fork..HEAD")"
    # fewest commits beyond the fork point wins; later (newer) refs win ties because of sort -V
    if [ -z "$best_dist" ] || [ "$dist" -le "$best_dist" ]; then best="$ref"; best_dist="$dist"; fi
  done
  echo "$best"
}

if [ -n "${VERIFY_BASE:-}" ]; then base="$VERIFY_BASE"
elif [ "${BASE_BRANCH_MODE:-}" = release ]; then base="$(pick_release)"; [ -z "$base" ] && base="$(fallback)"
else base="$(fallback)"; fi

if [ "${1:-}" = "--frozen" ]; then
  name="${base#origin/$PREFIX}"
  git rev-parse --verify -q "refs/tags/$FREEZE$name" >/dev/null && echo frozen || echo open
else
  echo "$base"
fi
