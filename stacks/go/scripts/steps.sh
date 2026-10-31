# Go checks for the shared verify engine (scripts/verify-core.sh). Sourced by verify.sh; do not run directly.
STACK_SOURCE_RE='\.go$'

# nearest go.mod directory for a file, empty if none
module_of() {
  dir="$(dirname "$1")"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    [ -f "$dir/go.mod" ] && { echo "$dir"; return; }
    dir="$(dirname "$dir")"
  done
  [ -f go.mod ] && echo "."
}

stack_run() {
  # golangci-lint config: LINT_CONFIG (project-relative, default <project-dir>/golangci.yml); without one its own discovery applies
  local LINT_CONFIG_ARG="" f mod dependents dir MODULES
  [ -f "$ROOT/${LINT_CONFIG:-$KIT_DIR/golangci.yml}" ] && LINT_CONFIG_ARG="--config=$ROOT/${LINT_CONFIG:-$KIT_DIR/golangci.yml}"

  MODULES="$(for f in $CHANGED_SRC; do [ -f "$f" ] && module_of "$f"; done | sort -u)"
  # a change to the shared module must rebuild everything that depends on it
  if [ -n "${SHARED_MODULE:-}" ] && echo "$MODULES" | grep -qx "$SHARED_MODULE"; then
    dependents="$(for dir in ${DEPENDENT_MODULES_GLOB:-}; do [ -f "$dir/go.mod" ] && echo "$dir"; done)"
    MODULES="$(printf '%s\n%s\n' "$MODULES" "$dependents" | sort -u | sed '/^$/d')"
  fi

  step "gofmt"
  for f in $CHANGED_SRC; do
    [ -f "$f" ] || continue
    [ -n "$(gofmt -l "$f")" ] && fail "gofmt: $f"
  done

  for mod in $MODULES; do
    [ -f "$mod/go.mod" ] || continue
    step "module $mod: vet + build"
    (cd "$mod" && go vet ./... 2>&1) || fail "go vet: $mod"
    (cd "$mod" && go build ./... 2>&1) || fail "go build: $mod"
    [ "$FAST" = 1 ] && continue

    # modules matching INTEGRATION_MODULE_GLOB (default tests/*) hit real infrastructure: vetted and built, never run here
    case "$mod" in
      ${INTEGRATION_MODULE_GLOB:-tests/*}) continue ;;
    esac
    step "module $mod: test"
    (cd "$mod" && go test ./... 2>&1) || fail "go test: $mod"

    if command -v golangci-lint >/dev/null 2>&1; then
      step "module $mod: golangci-lint (new code only)"
      (cd "$mod" && golangci-lint run ${LINT_CONFIG_ARG:+"$LINT_CONFIG_ARG"} --new-from-rev="$MERGE_BASE" ./... 2>&1) || fail "golangci-lint: $mod"
    else
      warn "golangci-lint not installed, lint skipped (brew install golangci-lint)"
    fi
  done
}
