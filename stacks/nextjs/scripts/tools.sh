#!/usr/bin/env bash
echo "required|node|install Node.js (see .nvmrc or package.json engines)"
echo "optional|pnpm|npm i -g pnpm (needed when the repo has pnpm-lock.yaml)"
echo "optional|yarn|npm i -g yarn (needed when the repo has yarn.lock)"
echo "optional|jq|brew install jq (needed to read package.json scripts)"
