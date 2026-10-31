# Next.js/React checks for the shared verify engine (scripts/verify-core.sh). Sourced by verify.sh; do not run directly.
STACK_SOURCE_RE='\.(tsx?|jsx?|mjs|cjs)$'

# shared Node helpers: next to this script (copy mode) or in stacks/_node (plugin mode)
for _n in "$ENGINE_DIR/node-lib.sh" "$ENGINE_DIR/../../_node/scripts/node-lib.sh"; do [ -f "$_n" ] && { . "$_n"; break; }; done
type node_check >/dev/null 2>&1 || { echo "node-lib.sh not found next to $0 or in stacks/_node/scripts/" >&2; exit 1; }

stack_run() {
  local f pkg PKGS rel files
  # packages of changed sources, plus packages whose package.json/tsconfig changed
  PKGS="$( { for f in $CHANGED_SRC; do [ -f "$f" ] && node_pkg_of "$f"; done
             for f in $(echo "$CHANGED" | grep -E '(^|/)(package\.json|tsconfig[^/]*\.json)$'); do [ -f "$f" ] && node_pkg_of "$f"; done; } | sort -u)"

  for pkg in $PKGS; do
    step "package $pkg: typecheck"
    if [ ! -f "$pkg/tsconfig.json" ]; then warn "typecheck skipped in $pkg: no tsconfig.json"
    else node_check "$pkg" typecheck typecheck tsc --noEmit; fi
    [ "$FAST" = 1 ] && continue

    step "package $pkg: lint"
    files=""
    for f in $CHANGED_SRC; do
      [ -f "$f" ] && [ "$(node_pkg_of "$f")" = "$pkg" ] || continue
      rel="$f"; [ "$pkg" != "." ] && rel="${f#"$pkg"/}"
      files="$files $rel"
    done
    # shellcheck disable=SC2086
    node_check "$pkg" lint lint eslint $files

    step "package $pkg: test"
    if ! node_has_script "$pkg" test; then warn "no test script in $pkg"
    elif jq -e '.scripts.test | test("no test specified")' "$pkg/package.json" >/dev/null 2>&1; then warn "test script in $pkg is the npm default, no tests"
    else node_check "$pkg" test test true; fi

    if [ "${VERIFY_BUILD:-0}" = 1 ] && node_has_script "$pkg" build; then
      step "package $pkg: next build"
      node_check "$pkg" build build next build
    fi
  done
}
