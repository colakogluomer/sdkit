#!/usr/bin/env bash
# Shared by every kit script and hook. Source it; do not execute it. Works under `set -eu`, bash 3.2 included; every function returns 0
# unless its comment says otherwise (a helper's own problem must never stop a hook).
#   sdkit_env_load <root>          find the project directory (KIT_DIR, KIT_ENV), then read sdkit.env and sdkit.local.env (the second wins)
#   sdkit_env_load_file <file>     read one settings file
#   sdkit_active_slug <root>       the task budget and ledger belong to (see below); prints nothing when there is none
#   sdkit_lock <path> / sdkit_unlock <path>   mutual exclusion around a read-modify-write of <path> (mkdir based, no flock needed)
#
# Settings files are DATA. They used to be sourced as shell, so any line in a committed sdkit.env ran at the next hook. Now each line is parsed:
#   KEY=value   KEY="value"   KEY='value'   export KEY=value   : "${KEY:=default}"   # comment   (blank lines)
# A value may use $NAME and ${NAME} (the value of a setting read before it); nothing else is expanded and nothing is executed.
# Any other line (command substitution, `;`, `&&`, a bare command, an unquoted space ...) is ignored and reported on stderr as
# "file:line: ignored (unsupported syntax)", without its content. SDKIT_ENV_QUIET=1 silences the report; SDKIT_ENV_BAD counts the lines.
# Keys that would change how the shell itself runs (PATH, IFS, BASH_ENV, LD_*, ...) are refused.
# Settings are shell variables, not environment variables, unless the line says `export`.

# The stack when STACK is empty. `go` is the documented default and what repos from before stacks existed (Go only) rely on.
SDKIT_DEFAULT_STACK=go

# sdkit_resolve_dir <root>: sets KIT_DIR and KIT_ENV. The project directory is .sdkit (sdkit.env) or, set up before 1.0, .agentkit, .claude
# or .codex (project.env); a KIT_DIR already set is tried first.
sdkit_resolve_dir() {
  local _d _e
  for _d in ${KIT_DIR:-} .sdkit .agentkit .claude .codex; do
    for _e in sdkit.env project.env; do
      [ -n "$_d" ] && [ -f "$1/$_d/$_e" ] && { KIT_DIR=$_d; KIT_ENV=$_e; return 0; }
    done
  done
  KIT_DIR="${KIT_DIR:-.sdkit}"; KIT_ENV="${KIT_ENV:-sdkit.env}"
  return 0
}

SDKIT_ENV_BAD=0
_sdkit_env_refused() {
  case "$1" in
    PATH|IFS|HOME|SHELL|ENV|BASH_ENV|BASH_*|CDPATH|GLOBIGNORE|PS1|PS2|PS4|PROMPT_COMMAND|SHELLOPTS|BASHOPTS|POSIXLY_CORRECT|FUNCNEST|TMPDIR|LD_*|DYLD_*|SDKIT_*|KIT_DIR|KIT_ENV|PROJECT_DIR|PLUGIN_ROOT) return 0 ;;
  esac
  return 1
}

# _sdkit_expand <text>: sets _SDKIT_OUT with $NAME and ${NAME} replaced by the current value of that variable. Returns 1 on any other `$`.
_sdkit_expand() {
  local s="$1" out="" name
  _SDKIT_OUT=""
  while :; do
    case "$s" in *'$'*) ;; *) _SDKIT_OUT="$out$s"; return 0 ;; esac
    out="$out${s%%\$*}"; s="${s#*\$}"
    if [[ $s =~ ^([A-Za-z_][A-Za-z0-9_]*)(.*)$ ]]; then name="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
    elif [[ $s =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ ]]; then name="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
    else return 1; fi
    eval "out=\"\$out\${$name:-}\""   # $name matched [A-Za-z_][A-Za-z0-9_]* above: a variable name, nothing else
  done
}

sdkit_env_load_file() {
  [ -f "$1" ] || return 0
  local file="$1" line key val n=0 exp cur
  local re_assign='^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
  local re_default='^:[[:space:]]+"?\$\{([A-Za-z_][A-Za-z0-9_]*):=([^$}"`\\[:space:]]*)\}"?[[:space:]]*$'
  local re_sq="^'([^']*)'[[:space:]]*(#.*)?\$"
  local re_dq='^"([^"\\`]*)"[[:space:]]*(#.*)?$'
  local re_bare='^([^[:space:];&|<>()\\`"'"'"']*)([[:space:]]+#.*)?[[:space:]]*$'
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ''|'#'*) continue ;; esac
    if [[ $line =~ $re_default ]]; then
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      _sdkit_env_refused "$key" && { _sdkit_env_bad "$file" "$n"; continue; }
      eval "cur=\"\${$key:-}\""
      [ -n "$cur" ] || printf -v "$key" '%s' "$val"
      continue
    fi
    exp=0
    case "$line" in export[[:space:]]*) exp=1; line="${line#export}"; line="${line#"${line%%[![:space:]]*}"}" ;; esac
    if [[ $line =~ $re_assign ]]; then
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      if _sdkit_env_refused "$key"; then _sdkit_env_bad "$file" "$n"; continue; fi
      if [[ $val =~ $re_sq ]]; then val="${BASH_REMATCH[1]}"
      elif [[ $val =~ $re_dq ]]; then
        _sdkit_expand "${BASH_REMATCH[1]}" || { _sdkit_env_bad "$file" "$n"; continue; }; val="$_SDKIT_OUT"
      elif [[ $val =~ $re_bare ]]; then
        _sdkit_expand "${BASH_REMATCH[1]}" || { _sdkit_env_bad "$file" "$n"; continue; }; val="$_SDKIT_OUT"
      else _sdkit_env_bad "$file" "$n"; continue; fi
      printf -v "$key" '%s' "$val"
      [ "$exp" = 1 ] && export "$key"
      continue
    fi
    _sdkit_env_bad "$file" "$n"
  done < "$file"
  return 0
}
_sdkit_env_bad() {
  SDKIT_ENV_BAD=$((SDKIT_ENV_BAD + 1))
  [ "${SDKIT_ENV_QUIET:-}" = 1 ] || printf 'sdkit: %s:%s: ignored (unsupported syntax; see docs/upgrading.md, "Settings files are parsed")\n' "${1##*/}" "$2" >&2
  return 0
}

sdkit_env_load() {
  sdkit_resolve_dir "$1"
  sdkit_env_load_file "$1/$KIT_DIR/$KIT_ENV"
  sdkit_env_load_file "$1/$KIT_DIR/sdkit.local.env"
  SDKIT_STACK_UNSET=0; [ -n "${STACK:-}" ] || SDKIT_STACK_UNSET=1
  STACK="${STACK:-$SDKIT_DEFAULT_STACK}"
  return 0
}

# sdkit_active_slug <root>: the task whose budget and ledger count. The task the phase machine has open (.sdd/state.json) wins, provided it
# has a work/<slug>/state.json; otherwise, as before, the most recently updated work/*/state.json. Needs KIT_DIR (sdkit_env_load sets it).
sdkit_active_slug() {
  local root="$1" s="" f
  f="$root/${KIT_DIR:-.sdkit}/.sdd/state.json"
  if [ -f "$f" ] && command -v jq >/dev/null 2>&1; then
    s="$(jq -r '.task // empty' "$f" 2>/dev/null)"
    case "$s" in ''|*[!A-Za-z0-9_.-]*) s="" ;; esac
    [ -n "$s" ] && [ -f "$root/${KIT_DIR:-.sdkit}/work/$s/state.json" ] && { printf '%s\n' "$s"; return 0; }
  fi
  f="$(ls -t "$root/${KIT_DIR:-.sdkit}"/work/*/state.json 2>/dev/null | head -1)"
  [ -n "$f" ] && basename "$(dirname "$f")"
  return 0
}

# sdkit_lock <path>: take <path>.lock (a directory, created atomically by mkdir). A holder keeps it for milliseconds, so a waiter that has been
# kept waiting for 3 s checks whether the owner process (the pid in the lock) is gone and, if so, breaks the lock; after 10 s any lock is assumed
# stuck and broken. Breaking is deliberately slow: breaking early could remove a lock a new owner has just taken. Always returns 0: a hook
# must not hang or fail on its own lock.
sdkit_lock() {
  local l="$1.lock" i=0 pid
  mkdir -p "$(dirname "$1")" 2>/dev/null
  [ -w "$(dirname "$1")" ] || return 0   # a directory nobody can write to can never be locked: do not wait for it
  while ! mkdir "$l" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
      pid="$(cat "$l/pid" 2>/dev/null)"
      if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ "$i" -ge 200 ]; then rm -rf "$l"; i=0; continue; fi
    fi
    sleep 0.05
  done
  echo "$$" > "$l/pid" 2>/dev/null
  return 0
}
sdkit_unlock() { rm -rf "$1.lock" 2>/dev/null; return 0; }
