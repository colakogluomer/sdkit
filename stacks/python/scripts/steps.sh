# Python checks for the shared verify engine (scripts/verify-core.sh). Sourced by verify.sh; do not run directly.
# Settings (sdkit.env): PY_RUNNER = command prefix for tools (e.g. "uv run", "poetry run"; default: from the lockfile).
STACK_SOURCE_RE='\.py$'

PROJECT_FILE_RE='(^|/)(pyproject\.toml|setup\.py|setup\.cfg|requirements[^/]*\.txt|pytest\.ini|tox\.ini|mypy\.ini)$'

# py_pkg_of <file>: nearest directory (up to ROOT) with a Python project file, "." when only the root has none
py_pkg_of() {
  local dir; dir="$(dirname "$1")"
  while :; do
    { [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/setup.cfg" ]; } && { echo "$dir"; return; }
    [ "$dir" = "." ] || [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  echo .
}

# py_runner <dir>: prefix that runs tools inside the project's environment
py_runner() {
  [ -n "${PY_RUNNER:-}" ] && { echo "$PY_RUNNER"; return; }
  [ -f "$1/uv.lock" ] || [ -f uv.lock ] && { echo "uv run"; return; }
  [ -f "$1/poetry.lock" ] || [ -f poetry.lock ] && { echo "poetry run"; return; }
  echo ""
}

# py_has <dir> <tool>: the tool is runnable in the project's environment
py_has() { local r; r="$(py_runner "$1")"; (cd "$1" && $r python3 -m "$2" --version >/dev/null 2>&1) || (cd "$1" && $r "$2" --version >/dev/null 2>&1); }

# py_configured <dir> <regex>: the project configures the tool (pyproject section or its own config file)
py_configured() {
  local d
  for d in "$1" .; do
    grep -qE "$2" "$d/pyproject.toml" "$d/setup.cfg" "$d/tox.ini" 2>/dev/null && return 0
  done
  return 1
}

stack_run() {
  local f pkg PKGS r files rel rc
  PKGS="$( { for f in $CHANGED_SRC; do [ -f "$f" ] && py_pkg_of "$f"; done
             for f in $(printf '%s\n' "$CHANGED" | grep -E "$PROJECT_FILE_RE" || true); do [ -f "$f" ] && py_pkg_of "$f"; done; } | sort -u)"

  for pkg in $PKGS; do
    r="$(py_runner "$pkg")"
    files=""
    for f in $CHANGED_SRC; do
      [ -f "$f" ] && [ "$(py_pkg_of "$f")" = "$pkg" ] || continue
      rel="$f"; [ "$pkg" != "." ] && rel="${f#"$pkg"/}"
      files="$files $rel"
    done

    step "package $pkg: syntax"
    # shellcheck disable=SC2086
    [ -z "$files" ] || (cd "$pkg" && $r python3 -m py_compile $files 2>&1) || fail "syntax: $pkg"
    [ "$FAST" = 1 ] && continue

    step "package $pkg: lint"
    if py_has "$pkg" ruff; then
      # shellcheck disable=SC2086
      [ -z "$files" ] || (cd "$pkg" && $r ruff check $files 2>&1) || fail "ruff: $pkg"
    elif py_configured "$pkg" 'tool\.(ruff|flake8)|\[flake8\]'; then warn "lint configured in $pkg but ruff is not installed"
    else warn "no linter configured in $pkg"; fi

    if py_configured "$pkg" 'tool\.mypy|\[mypy|mypy\.ini'; then
      step "package $pkg: mypy"
      if py_has "$pkg" mypy; then
        # shellcheck disable=SC2086
        (cd "$pkg" && $r mypy $files 2>&1) || fail "mypy: $pkg"
      else warn "mypy configured in $pkg but not installed"; fi
    fi

    step "package $pkg: test"
    if py_has "$pkg" pytest; then
      # pytest exit 5 = nothing collected: a warning, not a failure
      (cd "$pkg" && $r pytest -q 2>&1); rc=$?
      case "$rc" in 0) ;; 5) warn "pytest collected no tests in $pkg" ;; *) fail "pytest: $pkg" ;; esac
    elif [ -d "$pkg/tests" ] || [ -d "$pkg/test" ]; then
      (cd "$pkg" && $r python3 -m unittest discover -q 2>&1); rc=$?
      case "$rc" in 0) ;; 5) warn "unittest found no tests in $pkg (pytest-style tests need pytest installed)" ;; *) fail "unittest: $pkg" ;; esac
    else warn "no tests found in $pkg"; fi
  done
}
