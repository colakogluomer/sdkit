#!/usr/bin/env bash
# exit 0 when $1 contains a package.json that depends on next
while IFS= read -r p; do
  jq -e '(.dependencies.next // .devDependencies.next) // empty' "$p" >/dev/null 2>&1 && exit 0
done < <(find "${1:-.}" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null)
exit 1
