#!/usr/bin/env bash
# Project memory: durable facts, how-tos and small decisions the agents should not have to rediscover. Off unless MEMORY=1 in sdkit.env
# (every command is then a silent no-op). Entries live in <project-dir>/$MEMORY_DIR (default memory/); INDEX.md there is the only file
# loaded into a session, an entry is read only when its line looks relevant. known-pitfalls.md and adr/ stay as they are; INDEX links to them.
#   memory.sh status                         on/off, directory, entry count
#   memory.sh init                           create the directory and INDEX.md (never overwrites)
#   memory.sh add <fact|howto|decision> <slug> --title T [--body TEXT | --body -] [--verify-by YYYY-MM-DD] [--refs a,b]
#   memory.sh index                          rebuild INDEX.md from the entry files
#   memory.sh search <term>                  matching entries, at most 20 lines
#   memory.sh stale                          entries older than MEMORY_STALE_DAYS, past verify-by, or whose refs no longer exist
#   memory.sh autoload                       INDEX.md trimmed to MEMORY_INDEX_MAX lines (what the session hook injects); silent when off
#   memory.sh candidates <task-slug>         numbered `MEMORY: type | slug | title | body` lines from work/<task-slug>/notes.md
#   memory.sh promote <task-slug> <n...|all> add the chosen candidates (the user picks; MEMORY_PROMOTE=off disables, auto = closeout takes all)
# Entries never hold secrets: a body that looks like one is refused.
set -u
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
. "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; sdkit_env_load "$top"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
cmd="${1:-}"; [ $# -gt 0 ] && shift
[ -n "$cmd" ] || usage
case "$cmd" in status|init|add|index|search|stale|autoload|candidates|promote) ;; *) usage ;; esac

if [ "${MEMORY:-}" != 1 ]; then
  [ "$cmd" = status ] && echo "memory: off (set MEMORY=1 in sdkit.env)"
  [ "$cmd" = autoload ] || [ "$cmd" = status ] || echo "memory is off (set MEMORY=1 in sdkit.env)" >&2
  exit 0
fi

case "${MEMORY_DIR:-memory}" in /*) dir="${MEMORY_DIR}" ;; *) dir="$top/$KIT_DIR/${MEMORY_DIR:-memory}" ;; esac
index="$dir/INDEX.md"
pos_int() { case "${1:-}" in ''|*[!0-9]*|0) echo "$2" ;; *) echo "$1" ;; esac; }
index_max="$(pos_int "${MEMORY_INDEX_MAX:-}" 100)"; stale_days="$(pos_int "${MEMORY_STALE_DAYS:-}" 90)"
today="$(date +%F)"
fm() { sed -n "/^---\$/,/^---\$/{s/^$2: \{0,1\}//p;}" "$1" | head -1; }   # fm <file> <key>
entries() { ls "$dir"/*.md 2>/dev/null | grep -v '/INDEX\.md$'; }
valid_slug() { case "$1" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac; [ "$1" != INDEX ]; }
looks_secret() { printf '%s' "$1" | grep -qiE '(password|passwd|secret|api[_-]?key|token)[[:space:]]*[=:][[:space:]]*[^[:space:]]{6,}|-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'; }

write_index() {
  mkdir -p "$dir"; local tmp; tmp="$(mktemp)"
  { echo "# Knowledge index"
    echo "<!-- managed by scripts/memory.sh: one line per entry; read an entry only when its line looks relevant -->"
    local f
    for f in $(entries); do
      echo "- [$(fm "$f" type)] $(basename "$f" .md): $(fm "$f" title) (updated $(fm "$f" updated))"
    done
    echo "## Linked"
    [ -f "$top/$KIT_DIR/known-pitfalls.md" ] && echo "- $KIT_DIR/known-pitfalls.md: past bug classes"
    [ -d "$top/$KIT_DIR/adr" ] && echo "- $KIT_DIR/adr/: architecture decisions"
  } > "$tmp"; mv "$tmp" "$index"
}
entry_count() { entries | wc -l | tr -d ' '; }

add_entry() {   # add_entry <type> <slug> <title> <body> <verify-by> <refs>
  local type="$1" slug="$2" title="$3" body="$4" vby="$5" refs="$6"
  case "$type" in fact|howto|decision) ;; *) echo "type must be fact, howto or decision" >&2; return 2 ;; esac
  valid_slug "$slug" || { echo "slug may contain letters, digits, _ . - only (and not INDEX)" >&2; return 2; }
  [ -n "$title" ] || { echo "--title is required" >&2; return 2; }
  looks_secret "$title $body" && { echo "refused: the text looks like a secret; entries never hold secrets" >&2; return 2; }
  [ -f "$dir/$slug.md" ] && { echo "entry '$slug' exists; edit the file or pick another slug" >&2; return 1; }
  [ "$(entry_count)" -lt "$index_max" ] || { echo "index is full ($index_max entries, MEMORY_INDEX_MAX); remove or merge a stale entry first (memory.sh stale)" >&2; return 1; }
  mkdir -p "$dir"
  printf -- '---\ntype: %s\ntitle: %s\nupdated: %s\nverify-by: %s\nrefs: %s\n---\n%s\n' "$type" "$title" "$today" "$vby" "$refs" "$body" > "$dir/$slug.md"
  write_index; echo "$dir/$slug.md"
}

case "$cmd" in
  status) echo "memory: on, dir $dir, $(entry_count) entries (max $index_max)" ;;
  init) mkdir -p "$dir"; [ -f "$index" ] || write_index; echo "$index" ;;
  index) write_index; echo "$index" ;;
  add)
    type="${1:-}"; slug="${2:-}"; [ $# -ge 2 ] || usage; shift 2
    title=""; body=""; vby=""; refs=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) title="${2:-}"; shift ;; --body) body="${2:-}"; shift ;; --verify-by) vby="${2:-}"; shift ;; --refs) refs="${2:-}"; shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
      esac
      shift
    done
    [ "$body" = - ] && body="$(cat)"
    add_entry "$type" "$slug" "$title" "$body" "$vby" "$refs" ;;
  search)
    [ -n "${1:-}" ] || usage
    entries | while IFS= read -r f; do
      grep -iHn -- "$1" "$f" 2>/dev/null | grep -v ':[0-9]*:\(---\|updated:\|verify-by:\|refs:\)' | sed "s#^$dir/##" | cut -c1-200
    done | head -20 ;;
  stale)
    cutoff="$(date -v-"${stale_days}"d +%F 2>/dev/null || date -d "-${stale_days} days" +%F 2>/dev/null)"
    entries | while IFS= read -r f; do
      name="$(basename "$f" .md)"; upd="$(fm "$f" updated)"; vby="$(fm "$f" verify-by)"; why=""
      [ -n "$cutoff" ] && [ -n "$upd" ] && [ "$upd" \< "$cutoff" ] && why="$why older than ${stale_days} days;"
      [ -n "$vby" ] && ! [ "$vby" \> "$today" ] && why="$why verify-by $vby passed;"
      for r in $(fm "$f" refs | tr ',' ' '); do [ -e "$top/$r" ] || why="$why ref $r is gone;"; done
      [ -z "$why" ] || echo "$name:$why"
    done ;;
  autoload)
    [ "${MEMORY_AUTOLOAD:-1}" = 0 ] && exit 0
    [ -f "$index" ] && head -n "$index_max" "$index" ;;
  candidates|promote)
    task="${1:-}"; [ -n "$task" ] || usage; shift
    notes="$top/$KIT_DIR/work/$task/notes.md"
    [ "${MEMORY_PROMOTE:-ask}" = off ] && { echo "promotion is off (MEMORY_PROMOTE=off)" >&2; exit 0; }
    [ -f "$notes" ] || { echo "no notes at work/$task/notes.md" >&2; exit 0; }
    cands="$(grep -E '^MEMORY:' "$notes" | sed 's/^MEMORY:[[:space:]]*//')"
    if [ "$cmd" = candidates ]; then
      [ -n "$cands" ] && printf '%s\n' "$cands" | awk '{print NR": "$0}'; exit 0
    fi
    [ -n "${1:-}" ] || usage
    rc=0
    while IFS="$(printf '\t')" read -r n line; do
      pick=0; for a in "$@"; do [ "$a" = all ] || [ "$a" = "$n" ] && pick=1; done
      [ "$pick" = 1 ] || continue
      IFS='|' read -r t s ti b <<EOF
$line
EOF
      trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
      add_entry "$(trim "$t")" "$(trim "$s")" "$(trim "$ti")" "$(trim "${b:-}")" "" "" || rc=1
    done < <(printf '%s\n' "$cands" | awk '{print NR"\t"$0}')
    exit "$rc" ;;
esac
