# Files that hold both the kit's lines and the project's own (AGENTS.md, CLAUDE.md, settings.json, hooks.json, config.toml).
# Source it after lib.sh; do not execute. The developer edits only their own part; the kit rewrites only its part:
#   text files   a marked block (begin/end lines); everything outside it is the project's and is never touched
#   JSON files   only the keys/entries the kit owns are added or replaced; every other key and entry is left as is
# Every entry is recorded in <project-dir>/.scaffold-shared so sync/upgrade/doctor can refresh and check them.
# Needs: SCAFFOLD_ROOT, SCAFFOLD_VERSION, TARGET, KIT_DIR (and STACK, MODE, MARKETPLACE_URL for claude-settings).

SHARED_FILE_NAME=".scaffold-shared"

_render() { # <src-file>: substitute the kit placeholders
  sed -e "s#__KIT_ENV__#${KIT_ENV:-sdkit.env}#g" -e "s#__KIT_DIR__#${KIT_DIR}#g" -e "s#__KIT_HOOKS__#${KIT_HOOKS:-./$KIT_DIR/hooks}#g" "$1"
}

# --- text blocks -------------------------------------------------------------------------------------------------
# block_markers <style>: sets BEGIN_LINE / END_LINE. md = HTML comment, hash = # comment (TOML, YAML)
block_markers() {
  case "$1" in
    md)   BEGIN_LINE="<!-- spec-driven-kit:begin v$SCAFFOLD_VERSION. Managed by the kit: do not edit between the markers; write your own text outside them. -->"
          END_LINE="<!-- spec-driven-kit:end -->" ;;
    hash) BEGIN_LINE="# spec-driven-kit:begin v$SCAFFOLD_VERSION. Managed by the kit: do not edit between the markers; write your own settings outside them."
          END_LINE="# spec-driven-kit:end" ;;
  esac
}

# apply_block <dest-rel> <src-rel> <md|hash> <write|check> [new-file-header]
# check: exit 0 when the block in dest is current, 1 otherwise (nothing is written).
apply_block() {
  local dest="$TARGET/$1" src="$SCAFFOLD_ROOT/$2" style="$3" mode="$4" header="${5:-}" blk new tmp
  blk="$(mktemp)"; new="$(mktemp)"
  block_markers "$style"
  { echo "$BEGIN_LINE"; _render "$src" | block_filter "$1"; echo "$END_LINE"; } > "$blk"

  if [ ! -f "$dest" ]; then
    [ "$mode" = check ] && { rm -f "$blk" "$new"; return 1; }
    mkdir -p "$(dirname "$dest")"
    { [ -n "$header" ] && printf '%s\n\n' "$header"; cat "$blk"; } > "$dest"
    say "  wrote  $1 (new; your own text goes outside the kit block)"
  elif grep -q 'spec-driven-kit:begin' "$dest"; then
    grep -q 'spec-driven-kit:end' "$dest" || { say "  FAIL   $1 has a spec-driven-kit:begin marker but no :end marker; fix it by hand"; rm -f "$blk" "$new"; return 1; }
    awk -v blk="$blk" '
      /spec-driven-kit:begin/ { while ((getline l < blk) > 0) print l; skip = 1; next }
      /spec-driven-kit:end/   { skip = 0; next }
      !skip { print }' "$dest" > "$new"
    if cmp -s "$new" "$dest"; then [ "$mode" = check ] || say "  ok     $1 (kit block current)"
    else
      [ "$mode" = check ] && { rm -f "$blk" "$new"; return 1; }
      cp "$new" "$dest"; say "  update $1 (kit block only)"
    fi
  else
    [ "$mode" = check ] && { rm -f "$blk" "$new"; return 1; }
    { cat "$dest"; [ -z "$(tail -c1 "$dest")" ] || echo; echo; cat "$blk"; } > "$new" && cp "$new" "$dest"
    say "  append $1 (kit block added after your content; remove older kit-generated text from this file once, if any)"
  fi
  rm -f "$blk" "$new"
}

# the Codex config may already define [agents]; defining it twice is a TOML error, so the block then leaves it out
block_filter() {
  case "$1" in
    .codex/config.toml)
      if grep -qE '^\[agents\]' "$TARGET/$1" 2>/dev/null && ! awk '/spec-driven-kit:begin/{b=1} /spec-driven-kit:end/{b=0} b&&/^\[agents\]/{f=1} END{exit !f}' "$TARGET/$1"; then
        awk '/^\[agents\]/{skip=1; next} skip && /^\[/{skip=0} skip{next} {print}'
      else cat; fi ;;
    *) cat ;;
  esac
}

# --- JSON merges -------------------------------------------------------------------------------------------------
kit_hook_names() { ls "$SCAFFOLD_ROOT"/hooks/*.sh 2>/dev/null | xargs -n1 basename | sed 's/\.sh$//' | paste -sd'|' -; }

# merge_json <kind> <dest-rel> <src-rel> <write|check>
#   claude-settings   enabledPlugins / extraKnownMarketplaces added when missing; permissions allow/deny entries added when missing;
#                     hooks: kit-owned entries (a command under .../hooks/<kit hook>.sh) replaced, all others kept
#   hooks-grouped     Gemini-style {hooks:{Event:[{matcher,hooks:[{command}]}]}}: entries whose command runs adapt.sh are kit-owned
#   hooks-flat        Cursor-style {hooks:{event:[{command}]}}: same rule
merge_json() {
  local kind="$1" dest="$TARGET/$2" src="$SCAFFOLD_ROOT/$3" mode="$4" kit cur new re
  kit="$(mktemp)"; new="$(mktemp)"
  case "$kind" in
    claude-settings)
      local perms='[]'
      [ -f "$SCAFFOLD_ROOT/stacks/${STACK:-$SDKIT_DEFAULT_STACK}/permissions.txt" ] && perms="$(jq -R . < "$SCAFFOLD_ROOT/stacks/${STACK:-$SDKIT_DEFAULT_STACK}/permissions.txt" | jq -s .)"
      sed "s#__MARKETPLACE_URL__#${MARKETPLACE_URL:-https://example.invalid/spec-driven-kit.git}#g" "$src" | _render /dev/stdin \
        | jq --argjson extra "$perms" '.permissions.allow += $extra' > "$kit"
      re="/hooks/($(kit_hook_names))\\.sh" ;;
    *) _render "$src" > "$kit"; re='adapt\.sh' ;;
  esac
  jq empty "$kit" 2>/dev/null || { say "  FAIL   $3 renders to invalid JSON"; rm -f "$kit" "$new"; return 1; }
  if [ -f "$dest" ]; then
    jq empty "$dest" 2>/dev/null || { say "  FAIL   $2 is not valid JSON; fix it, then re-run"; rm -f "$kit" "$new"; return 1; }
    cur="$dest"
  else cur=/dev/null; echo '{}' > "$new.empty"; cur="$new.empty"; fi

  jq --slurpfile kit "$kit" --arg re "$re" --arg kind "$kind" '
    ($kit[0]) as $k
    | def addmissing($key): .[$key] = ((.[$key] // {}) as $c | ($k[$key] // {}) as $n | $n + $c);          # existing keys win
    def addlist($path): setpath($path; ((getpath($path) // []) as $c | $c + [ (($k | getpath($path)) // [])[] | select(. as $x | $c | index($x) | not) ]));
    def owned: ((.command // "") | test($re));
    def grouped_merge:
        .hooks = (
          ((.hooks // {}) | with_entries(.value |= (map(.hooks |= map(select(owned | not)) | select((.hooks // []) | length > 0))))) as $mine
          | reduce (($k.hooks // {}) | keys[]) as $e ($mine; .[$e] = ((.[$e] // []) + $k.hooks[$e])));
    def flat_merge:
        .hooks = (
          ((.hooks // {}) | with_entries(.value |= map(select(owned | not)))) as $mine
          | reduce (($k.hooks // {}) | keys[]) as $e ($mine; .[$e] = ((.[$e] // []) + $k.hooks[$e])));
    if $kind == "claude-settings" then
        addmissing("enabledPlugins") | addmissing("extraKnownMarketplaces")
        | addlist(["permissions","allow"]) | addlist(["permissions","deny"])
        | if ($k.hooks // null) != null then grouped_merge else . end
      elif $kind == "hooks-grouped" then
        grouped_merge | addlist(["context","fileName"])
      else
        (if .version == null and $k.version != null then .version = $k.version else . end) | flat_merge
      end' "$cur" > "$new" || { say "  FAIL   could not merge $2"; rm -f "$kit" "$new" "$new.empty"; return 1; }

  if [ -f "$dest" ] && [ "$(jq -S . "$new")" = "$(jq -S . "$dest")" ]; then
    [ "$mode" = check ] || say "  ok     $2 (kit entries current)"
    rm -f "$kit" "$new" "$new.empty"; return 0
  fi
  [ "$mode" = check ] && { rm -f "$kit" "$new" "$new.empty"; return 1; }
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ]; then say "  merge  $2 (kit entries only; your entries are kept)"; else say "  wrote  $2"; fi
  jq . "$new" > "$dest"
  rm -f "$kit" "$new" "$new.empty"
}

# --- dispatch and record ------------------------------------------------------------------------------------------
# apply_shared <kind> <dest-rel> <src-rel> <write|check>
apply_shared() {
  case "$1" in
    block-md)   apply_block "$2" "$3" md "$4" "# ${PROJECT_NAME:-$(basename "$TARGET")}" ;;
    block-hash) apply_block "$2" "$3" hash "$4" ;;
    claude-settings|hooks-grouped|hooks-flat) merge_json "$1" "$2" "$3" "$4" ;;
    *) say "  FAIL   unknown shared kind '$1'"; return 1 ;;
  esac
}

# shared_file <kit-dir-relative record file>
shared_record_file() { echo "$TARGET/$KIT_DIR/$SHARED_FILE_NAME"; }

# install_shared <kind> <dest-rel> <src-rel>: apply now and remember it for sync/doctor
install_shared() {
  apply_shared "$1" "$2" "$3" write || true
  local f; f="$(shared_record_file)"; mkdir -p "$(dirname "$f")"; touch "$f"
  grep -qxF "$(printf '%s\t%s\t%s' "$1" "$2" "$3")" "$f" || printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$f"
}

# refresh_shared <write|check>: every recorded entry; returns 1 in check mode when something is out of date
refresh_shared() {
  local f rc=0 kind dest src; f="$(shared_record_file)"
  [ -f "$f" ] || return 0
  while IFS="$(printf '\t')" read -r kind dest src; do
    [ -n "$kind" ] || continue
    if [ "$1" = check ]; then
      apply_shared "$kind" "$dest" "$src" check || { say "  drift   $dest (kit part is out of date)"; rc=1; }
    else apply_shared "$kind" "$dest" "$src" write || rc=1; fi
  done < "$f"
  return $rc
}
