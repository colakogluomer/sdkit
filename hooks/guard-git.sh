#!/usr/bin/env bash
# PreToolUse(Bash): enforce the release-branch flow's git rules (described in the project's project.md).
#   deny  merging/pulling/rebasing the base branch into a feature branch (leaks untested work into the release)
#   deny  cutting a new branch from the base branch while BASE_BRANCH_MODE=release
#   ask   pushing straight to an env branch listed in PROTECTED_BRANCHES (those move only through the project's release tooling)
. "$(dirname "$0")/lib.sh"
[ "${BASE_BRANCH_MODE:-}" = release ] || exit 0   # module is off for projects that do not use a release-branch flow
command="$(jget .tool_input.command)"
case "$command" in *git*) ;; *) exit 0 ;; esac

base="${BASE_BRANCH:-develop}"
current="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
base_ref="(origin/)?$base"
resolve_cmd="$(kit_cmd "${DIFF_BASE_CMD:-}" "scripts/resolve-base.sh")"
release="$( [ -x "$resolve_cmd" ] && cd "$PROJECT_DIR" && "$resolve_cmd" 2>/dev/null )"

# a feature branch is anything that is neither the base nor a release/env branch
is_feature=0
case "$current" in "$base"|"${RELEASE_BRANCH_PREFIX:-release/}"*|HEAD|"") ;; *) is_feature=1 ;; esac
IFS=',' read -r -a env_branches <<< "${PROTECTED_BRANCHES:-}"
for env in "${env_branches[@]}"; do [ "$env" = "$current" ] && is_feature=0; done

if [ "$is_feature" = 1 ] && printf '%s' "$command" | grep -qE "git +(merge|pull|rebase)( +-[-a-zA-Z]+)* +(origin +)?$base_ref( |$|;|&)"; then
  decide deny "Do not bring '$base' into feature branch '$current': it carries work that has not passed test into the release. Rebase/merge onto ${release:-the release branch} only (see the release flow in $KIT_DIR/project.md)."
fi

if [ "${BASE_BRANCH_MODE:-}" = release ]; then
  # git checkout -b N [start] | git switch -c N [start] | git branch N [start]
  start="$(printf '%s' "$command" | sed -nE 's/.*git +(checkout +-b|switch +-c|branch) +[^ ;&|]+ +([^ ;&|-][^ ;&|]*).*/\2/p' | head -1)"
  creates=0; printf '%s' "$command" | grep -qE "git +(checkout +-b|switch +-c) +[^ ;&|]+" && creates=1
  if [ "$creates" = 1 ]; then
    cut_from_base=0
    if [ -n "$start" ]; then printf '%s' "$start" | grep -qE "^$base_ref$" && cut_from_base=1
    elif [ "$current" = "$base" ]; then cut_from_base=1; fi
    [ "$cut_from_base" = 1 ] && \
      decide deny "Cut feature branches from the active release branch, not '$base': git checkout -b <name> ${release:-origin/release/<name>} (see the release flow in $KIT_DIR/project.md)."
  fi
fi

for env in "${env_branches[@]}"; do
  [ -n "$env" ] && printf '%s' "$command" | grep -qE "git +push\b[^;&|]*[ :]$env( |$|;|&)" && \
    decide ask "Pushing straight to env branch '$env'. These branches move only through the project's release tooling."
done
exit 0
