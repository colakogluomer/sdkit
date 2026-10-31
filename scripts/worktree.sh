#!/usr/bin/env bash
# Isolated git worktrees for parallel tasks.
#   worktree.sh add <task-id>     create ../<repo>-wt/<task-id> on branch wt/<current-branch>/<task-id>, print its path
#   worktree.sh path <task-id>    print the worktree path (give it to the role as WORKTREE in the handoff)
#   worktree.sh merge <task-id> [tasks.md]   merge that branch into the current branch (no fast-forward); abort and exit 1 on conflict.
#                                 With tasks.md (or $TASKS_FILE) the task's changes are first checked against its `writes:` set
#   worktree.sh clean             remove worktrees whose branch is already merged into the current branch
#   worktree.sh list              show task worktrees
# Run from the worktree of the branch the tasks belong to (the integration point for the wave).
set -eu
cmd="${1:-}"; id="${2:-}"; tasks="${3:-${TASKS_FILE:-}}"
top="$(git rev-parse --show-toplevel)"
cur="$(git rev-parse --abbrev-ref HEAD)"
[ "$cur" != HEAD ] || { echo "detached HEAD: check out the task's branch first" >&2; exit 1; }
root="$(dirname "$top")/$(basename "$top")-wt"
br() { echo "wt/$cur/$1"; }

case "$cmd" in
  add)
    [ -n "$id" ] || { echo "usage: worktree.sh add <task-id>" >&2; exit 2; }
    case "$id" in *[!A-Za-z0-9_.-]*) echo "task id may contain letters, digits, _ . - only" >&2; exit 2 ;; esac
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "commit or stash first: the worktree starts from HEAD" >&2; exit 1; }
    mkdir -p "$root"
    git worktree add -q -b "$(br "$id")" "$root/$id" HEAD
    echo "$root/$id"
    ;;
  path)
    [ -n "$id" ] && [ -d "$root/$id" ] || { echo "no worktree for task '$id' (worktree.sh add first)" >&2; exit 1; }
    echo "$root/$id"
    ;;
  merge)
    [ -n "$id" ] || { echo "usage: worktree.sh merge <task-id> [tasks.md]" >&2; exit 2; }
    [ -z "$(git -C "$root/$id" status --porcelain 2>/dev/null)" ] || { echo "task $id has uncommitted changes; commit them in its worktree first" >&2; exit 1; }
    if [ -n "$tasks" ]; then
      "$(dirname "$0")/check-writes.sh" "$tasks" "$id" "$(git merge-base HEAD "$(br "$id")")" "$(br "$id")" \
        || { echo "task $id left its writes: set; not merged. Fix the plan or revert the stray files." >&2; exit 1; }
    fi
    if ! git merge --no-ff -m "merge task $id" "$(br "$id")"; then
      git merge --abort || true
      echo "conflict merging $id: the write sets overlapped; fix the plan (references/parallel.md)" >&2
      exit 1
    fi
    ;;
  clean)
    for b in $(git for-each-ref --format='%(refname:short)' "refs/heads/wt/$cur/"); do
      tid="${b#wt/$cur/}"
      if git merge-base --is-ancestor "$b" HEAD; then
        git worktree remove --force "$root/$tid" 2>/dev/null || true
        git branch -q -d "$b" && echo "removed $tid"
      fi
    done
    ;;
  list) git worktree list | grep -F "$root" || echo "no task worktrees" ;;
  *) echo "usage: worktree.sh add|path|merge|clean|list [task-id]" >&2; exit 2 ;;
esac
