# Helpers shared by the Node-based stacks (nextjs, react-native). Source it from steps.sh; do not run it.
# Needs ROOT from the verify core. Settings (sdkit.env): NODE_PM (npm|pnpm|yarn|bun; default: from the lockfile).

# node_pkg_of <file>: nearest directory (up to ROOT) holding a package.json, empty if none
node_pkg_of() {
  local dir; dir="$(dirname "$1")"
  while :; do
    [ -f "$dir/package.json" ] && { echo "$dir"; return; }
    [ "$dir" = "." ] || [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  [ -f package.json ] && echo "."
}

# node_pm <dir>: package manager for the package (NODE_PM, else the nearest lockfile going up, else npm)
node_pm() {
  [ -n "${NODE_PM:-}" ] && { echo "$NODE_PM"; return; }
  local dir="$1"
  while :; do
    [ -f "$dir/pnpm-lock.yaml" ] && { echo pnpm; return; }
    [ -f "$dir/yarn.lock" ] && { echo yarn; return; }
    { [ -f "$dir/bun.lockb" ] || [ -f "$dir/bun.lock" ]; } && { echo bun; return; }
    [ -f "$dir/package-lock.json" ] && { echo npm; return; }
    [ "$dir" = "." ] || [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  echo npm
}

# node_has_script <dir> <name>: package.json defines that script
node_has_script() { jq -e --arg s "$2" '.scripts[$s] // empty' "$1/package.json" >/dev/null 2>&1; }
# node_has_dep <dir> <package>: listed in dependencies or devDependencies
node_has_dep() { jq -e --arg p "$2" '(.dependencies[$p] // .devDependencies[$p]) // empty' "$1/package.json" >/dev/null 2>&1; }

# node_run <dir> <script>: run a package.json script with the right package manager
node_run() { (cd "$1" && "$(node_pm "$1")" run "$2" 2>&1); }
# node_exec <dir> <bin> [args...]: run a locally installed binary (never downloads)
node_exec() {
  local dir="$1" bin="$2"; shift 2
  [ -x "$dir/node_modules/.bin/$bin" ] || [ -x "$ROOT/node_modules/.bin/$bin" ] || return 127
  case "$(node_pm "$dir")" in
    pnpm) (cd "$dir" && pnpm exec "$bin" "$@" 2>&1) ;;
    yarn) (cd "$dir" && yarn "$bin" "$@" 2>&1) ;;
    bun)  (cd "$dir" && bunx --no-install "$bin" "$@" 2>&1) ;;
    *)    (cd "$dir" && npx --no-install "$bin" "$@" 2>&1) ;;
  esac
}

# node_check <dir> <label> <script> <bin> [args...]: run `script` if package.json has it, else the local binary, else warn and skip
node_check() {
  local dir="$1" label="$2" script="$3" bin="$4"; shift 4
  if [ ! -d "$dir/node_modules" ] && [ ! -d "$ROOT/node_modules" ]; then warn "$label skipped in $dir: dependencies not installed ($(node_pm "$dir") install)"; return 0; fi
  if node_has_script "$dir" "$script"; then node_run "$dir" "$script" || fail "$label: $dir"
  elif node_exec "$dir" "$bin" "$@"; then :
  else
    local rc=$?
    if [ "$rc" = 127 ]; then warn "$label skipped in $dir: no '$script' script and no local $bin"; else fail "$label: $dir"; fi
  fi
}
