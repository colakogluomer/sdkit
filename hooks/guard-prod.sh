#!/usr/bin/env bash
# PreToolUse(Bash): ask before state-changing kubectl against a production context.
. "$(dirname "$0")/lib.sh"
[ -n "${PROD_KUBE_CLUSTERS:-}" ] || exit 0   # module is off unless the project names its production clusters
command="$(jget .tool_input.command)"
case "$command" in *kubectl*) ;; *) exit 0 ;; esac

mutating='(apply|delete|rollout|scale|patch|edit|replace|create|run|set|annotate|label|exec|cp|drain|cordon|taint)'
printf '%s' "$command" | grep -qE "kubectl([^|;&]*) $mutating( |$)" || exit 0

# explicit --context wins over the active one
target="$(printf '%s' "$command" | grep -oE -- '--context[= ][^ ]+' | head -1 | sed -E 's/--context[= ]//')"
[ -z "$target" ] && target="$(kubectl config current-context 2>/dev/null)"

# match on the cluster the context points to, so every alias of a prod cluster is covered
cluster="$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$target')].context.cluster}" 2>/dev/null)"
IFS=',' read -r -a prod_clusters <<< "${PROD_KUBE_CLUSTERS:-}"
for prod in "${prod_clusters[@]}"; do
  [ -n "$prod" ] && case "$cluster" in *"$prod") \
    decide ask "Mutating kubectl against PRODUCTION cluster '$prod' (context '$target'). Confirm this is intended." ;; esac
done
exit 0
