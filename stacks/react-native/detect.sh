#!/usr/bin/env bash
# exit 0 when $1 contains a package.json depending on react-native (bare and Expo apps both do)
while IFS= read -r p; do
  jq -e '(.dependencies["react-native"] // .devDependencies["react-native"] // .peerDependencies["react-native"]) // empty' "$p" >/dev/null 2>&1 && exit 0
done < <(find "${1:-.}" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null)
exit 1
