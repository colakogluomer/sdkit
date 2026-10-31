#!/usr/bin/env bash
# Generate host-specific role files from the neutral definitions in core/roles/.
#   Claude Code  -> agents/<role>.md
#   Codex        -> adapters/codex/agents/<role>.toml and adapters/codex/config.toml.snippet
#   OpenCode     -> adapters/opencode/agents/<role>.md
#   Cursor       -> adapters/cursor/agents/<role>.md
#   Gemini CLI   -> adapters/gemini/agents/<role>.md
# A role with `deep: <tier>` also produces <role>-deep at that tier (same body).
# Per-host code lives in bin/emit/<host>.sh (begin / role). Host-owned hook/plugin files in adapters/ are written by hand.
# Usage: build-adapters.sh [--check]
#   --check  build into a temp dir and fail if the committed files differ (use before releasing)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/core/tiers.env"
. "$ROOT/core/hosts.env"
HOSTS="claude codex opencode cursor gemini"
for h in $HOSTS; do . "$ROOT/bin/emit/$h.sh"; done

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1
OUT="$ROOT"
if [ "$CHECK" = 1 ]; then OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT; fi

# field <file> <key>: value of a frontmatter key
field() { awk -v k="$2" 'BEGIN{f=0} /^---$/{f++; next} f==1 && index($0,k":")==1 {sub("^"k":[ ]*",""); print; exit}' "$1"; }
# body <file>: everything after the closing frontmatter marker
body() { awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "$1"; }

PREAMBLE='`<project-dir>` below is the directory that holds `sdkit.env`: `.sdkit/` (a repo set up before 1.0 may still use `.agentkit/`, `.claude/` or `.codex/` with `project.env`; the handoff names it).'
for h in $HOSTS; do "emit_${h}_begin"; done

BODYFILE="$(mktemp)"; trap 'rm -f "$BODYFILE"; [ "$CHECK" = 1 ] && rm -rf "$OUT"' EXIT
count=0
emit_all() { for h in $HOSTS; do "emit_${h}_role"; done; count=$((count + 1)); }
for f in "$ROOT"/core/roles/*.md; do
  [ "$(basename "$f")" = README.md ] && continue
  name="$(field "$f" name)"; desc="$(field "$f" description)"; kind="$(field "$f" kind)"
  access="$(field "$f" access)"; tier="$(field "$f" tier)"; indep="$(field "$f" independent)"; deep="$(field "$f" deep)"
  [ -n "$name" ] && [ -n "$desc" ] && [ -n "$access" ] && [ -n "$tier" ] || { echo "bad frontmatter: $f" >&2; exit 1; }
  [ "$kind" = subagent ] || continue
  for t in $tier $deep; do case "$t" in light|standard|strong) ;; *) echo "bad tier '$t' in $f" >&2; exit 1 ;; esac; done
  case "$access" in
    read-only) RO=1 ;;
    docs|tests|code|infra) RO=0 ;;
    *) echo "bad access '$access' in $f" >&2; exit 1 ;;
  esac
  body "$f" > "$BODYFILE"
  NOTE="Generated from core/roles/$name.md by bin/build-adapters.sh; edit the source."
  [ "$indep" = true ] && NOTE="$NOTE Independent role: never give it the implementer's reasoning."

  NAME="$name"; DESC="$desc"; ACCESS="$access"; INDEP="$indep"; T="$(printf '%s' "$tier" | tr a-z A-Z)"
  emit_all
  if [ -n "$deep" ]; then
    NAME="$name-deep"; DESC="$desc Strong-tier variant for high-risk work."; T="$(printf '%s' "$deep" | tr a-z A-Z)"
    emit_all
  fi
done

if [ "$CHECK" = 1 ]; then
  rc=0
  for d in agents adapters/codex adapters/opencode/agents adapters/cursor/agents adapters/gemini/agents; do
    diff -r "$OUT/$d" "$ROOT/$d" >/dev/null 2>&1 || { echo "out of date: $d (run bin/build-adapters.sh)"; rc=1; }
  done
  [ "$rc" = 0 ] && echo "adapters up to date ($count role files)"
  exit "$rc"
fi
echo "built $count role files: agents/ (Claude Code), adapters/{codex,opencode,cursor,gemini}/"
