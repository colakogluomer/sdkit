#!/usr/bin/env bash
echo "required|node|install Node.js (see .nvmrc or engines in package.json)"
echo "required|jq|brew install jq (used to read package.json)"
echo "optional|prettier|install it as a devDependency (format-on-edit is skipped without it)"
echo "optional|watchman|brew install watchman (Metro and jest-haste-map file watching)"
