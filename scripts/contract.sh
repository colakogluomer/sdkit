#!/usr/bin/env bash
# Agent contracts (F02): check that a handoff and an agent's final answer are well-formed and consistent, deterministically, with no model.
# A valid contract says the exchange is well-formed. It never says the work is done or correct: it does not touch the phase machine
# (sdd.sh), the verdict (parse-verdict.sh), tests or git. Spec and limits: docs/design-contracts.md; format: skills/spec-driven-dev/references/contract.md.
#   contract.sh issue FILE|- [--role R] [--task S] [--check-only] [--source X]
#       validate a handoff that carries `CONTRACT: 1` and `ID: <slug>/<label>` and register it (work/<slug>/contracts/<label>.json).
#       `RETRY-OF: <id>` supersedes an earlier id (invalid or interrupted) of the same role.
#   contract.sh check-result FILE|- [--id ID] [--role R] [--task S] [--cwd DIR] [--record] [--legacy-ok] [--source X]
#       validate the single `HANDOFF-RESULT/1 | id: .. | role: .. | status: .. | artifacts: .. | blockers: .. | next: ..` line of an answer.
#       --record stores the outcome in the registry (the first valid result wins; a second is `duplicate`).
#       --legacy-ok: an answer without the line is fine when no handoff of that role is waiting (hosts that cannot tell which handoff an
#       answer belongs to, i.e. the Claude Code hook).
#   contract.sh close ID [--reason interrupted]     the agent never answered (host error, killed): the id can only be retried
#   contract.sh pending [--role R] [--task S]       ids issued and not answered yet
#   contract.sh status [slug]                       every id of a task: state, role, status, reason
#   contract.sh id FILE|-                           print the ID of a handoff
# Output, one line. issue: CONTRACT=valid|invalid stage=handoff id=.. role=.. [reason=.. detail]. check-result adds status=.. .
# Exit: 0 valid (check-result: status done), 1 valid but the agent reports partial|blocked|failed, 2 invalid. exit 0 is not "verified".
# Reasons: no-result malformed unsupported-version missing-field bad-value inconsistent id-mismatch role-mismatch task-mismatch unknown-id
#          duplicate stale unsafe-path missing-artifact out-of-scope
# Telemetry (TELEMETRY=1): one contract.check event per call, plus failure/contract when invalid. Sizes only, never the text.
set -u
cmd="${1:-}"; [ $# -gt 0 ] && shift
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null || { echo "contract.sh needs jq" >&2; exit 2; }
top="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$here/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 2; }
SDKIT_ENV_QUIET=1 sdkit_env_load "$top"
CV=1   # the contract version this script speaks
US="$(printf '\037')"   # field separator for values read back from the registry (not whitespace, so empty fields survive `read`)

role_file() { local c; for c in "$here/../core/roles/$1.md" "$top/$KIT_DIR/roles/$1.md"; do [ -f "$c" ] && { echo "$c"; return 0; }; done; return 1; }
role_meta() {  # role_meta <file>: sets R_ACCESS and R_KIND from the front matter (one process)
  local k v
  R_ACCESS=""; R_KIND=""
  while IFS='|' read -r k v; do case "$k" in access) R_ACCESS="$v" ;; kind) R_KIND="$v" ;; esac
  done <<< "$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1 && (index($0,"access:")==1 || index($0,"kind:")==1) {i=index($0,":"); v=substr($0,i+1); sub(/^[ ]*/,"",v); print substr($0,1,i-1) "|" v} f>1{exit}' "$1")"
}

trim() { T="$1"; T="${T#"${T%%[![:space:]]*}"}"; T="${T%"${T##*[![:space:]]}"}"; }   # trims into $T: no subshell per call

# safe_rel <path>: a plain repo-relative path (no absolute, ~, .., .git, glob or odd characters)
safe_rel() {
  case "$1" in ''|/*|~*|-*|*[!A-Za-z0-9_./@+-]*) return 1 ;; esac
  case "/$1/" in */../*|*/./*|*//*|*/.git/*) return 1 ;; esac
  return 0
}
# inside_root <base dir> <path>: an existing path whose real location stays under the base (symlinks resolved)
inside_root() {
  local b d
  b="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  d="$(cd "$(dirname "$1/$2")" 2>/dev/null && pwd -P)" || return 1
  case "$d/" in "$b"/*|"$b/") return 0 ;; esac
  return 1
}
in_scope() {  # in_scope <path> <comma list of prefixes>: same rule as check-writes.sh (a file or a directory prefix)
  local f="$1" p
  while IFS= read -r p; do trim "$p"; p="${T%/}"; [ -z "$p" ] && continue; { [ "$f" = "$p" ] || [ "${f#"$p"/}" != "$f" ]; } && return 0; done <<< "$(printf '%s' "$2" | tr ',' '\n')"
  return 1
}

valid_part() { case "$1" in ''|.|..|*[!A-Za-z0-9_.-]*) return 1 ;; esac; [ "${#1}" -le 64 ]; }   # a task slug or a label: letters, digits, _ . -
valid_id() { case "$1" in */*/*) return 1 ;; */*) valid_part "${1%%/*}" && valid_part "${1#*/}" ;; *) return 1 ;; esac; }
reg_dir() { printf '%s/%s/work/%s/contracts' "$top" "$KIT_DIR" "$1"; }
reg_file() { printf '%s/%s.json' "$(reg_dir "$1")" "$2"; }   # reg_file <slug> <label>
reg_get() { jq -r "$3 // empty" "$(reg_file "$1" "$2")" 2>/dev/null; }
reg_update() {  # reg_update <slug> <label> <jq filter> [jq args]: under the file's lock, so parallel agents never lose an update
  local f; f="$(reg_file "$1" "$2")"; local flt="$3"; shift 3
  [ -f "$f" ] || return 1
  sdkit_lock "$f"
  local tmp; tmp="$(mktemp "$f.XXXXXX")"
  jq "$@" "$flt" "$f" > "$tmp" && mv "$tmp" "$f"; local rc=$?; rm -f "$tmp"
  sdkit_unlock "$f"; return $rc
}

tele() {  # tele <outcome> <stage> <id> <role> <status> <reason> <bytes> <source>
  [ "${TELEMETRY:-}" = 1 ] && [ -x "$here/telemetry.sh" ] || return 0
  local slug="${3%%/*}"; [ -n "$3" ] || slug=""
  "$here/telemetry.sh" emit contract.check ${slug:+--task "$slug"} --outcome "$1" --stage "$2" --contract "${3#*/}" --role "$4" --status "$5" --reason "$6" \
    --bytes "$7" --cv "$CV" --source "${8:-contract}" >/dev/null 2>&1
  [ "$1" = invalid ] && "$here/telemetry.sh" emit failure ${slug:+--task "$slug"} --category contract --reason "$6" --role "$4" --source "${8:-contract}" >/dev/null 2>&1
  return 0
}

active_task() { local t="${1:-}"; [ -n "$t" ] || t="$(sdkit_active_slug "$top")"; printf '%s' "$t"; }

# ---- shared exits -------------------------------------------------------------------------------------------------------------------
STAGE=""; XID=""; XROLE=""; XSTATUS=""; BYTES=0; SRC="contract"
bad() {  # bad <reason> <detail>: report an invalid contract and leave
  [ "${NOEMIT:-0}" = 1 ] || tele invalid "$STAGE" "$XID" "$XROLE" "$XSTATUS" "$1" "$BYTES" "$SRC"
  if [ "${RECORD:-0}" = 1 ] && [ "$STAGE" = result ] && valid_id "$XID" && [ -f "$(reg_file "${XID%%/*}" "${XID#*/}")" ]; then
    reg_update "${XID%%/*}" "${XID#*/}" 'if .state == "issued" or .state == "invalid" then .state="invalid" | .reason=$r | .updated=$t else . end' --arg r "$1" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null
  fi
  echo "CONTRACT=invalid stage=$STAGE${XID:+ id=$XID}${XROLE:+ role=$XROLE} reason=$1: $2"
  exit 2
}
read_text() {  # read_text <file|-> -> $TEXT, $BYTES
  if [ "$1" = - ]; then TEXT="$(cat)"; else TEXT="$(cat "$1" 2>/dev/null)" || { echo "contract: cannot read $1" >&2; exit 2; }; fi
  BYTES="$(printf '%s' "$TEXT" | wc -c | tr -d ' ')"
}
scan_handoff() {  # one awk pass: the rest of the first line that starts with KEY: for each key of the brief -> $K_<KEY>
  local k v
  K_CONTRACT=""; K_ID=""; K_ROLE=""; K_TASK=""; K_READ=""; K_SCOPE=""; K_OUT=""; K_WORKTREE=""; K_RETRY=""
  while IFS='|' read -r k v; do
    case "$k" in CONTRACT) K_CONTRACT="$v" ;; ID) K_ID="$v" ;; ROLE) K_ROLE="$v" ;; TASK) K_TASK="$v" ;; READ) K_READ="$v" ;; SCOPE) K_SCOPE="$v" ;;
      OUT) K_OUT="$v" ;; WORKTREE) K_WORKTREE="$v" ;; RETRY-OF) K_RETRY="$v" ;; esac
  done <<< "$(printf '%s\n' "$TEXT" | awk 'BEGIN{n=split("CONTRACT ID ROLE TASK READ SCOPE OUT WORKTREE RETRY-OF", ks, " "); for (i = 1; i <= n; i++) want[ks[i]] = 1}
    { l = $0; sub(/^[ \t]+/, "", l); p = index(l, ":"); if (p > 1) { k = substr(l, 1, p - 1); if ((k in want) && !(k in got)) { got[k] = 1; v = substr(l, p + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print k "|" v } } }')"
}
word1() { W="${1%%[[:space:]]*}"; }   # first word into $W

# ---- issue --------------------------------------------------------------------------------------------------------------------------
cmd_issue() {
  local file="${1:-}"; [ $# -gt 0 ] && shift
  local role="" task="" check_only=0
  while [ $# -gt 0 ]; do case "$1" in --role) role="$2"; shift ;; --task) task="$2"; shift ;; --check-only) check_only=1 ;; --source) SRC="$2"; shift ;; esac; shift; done
  [ -n "$file" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
  STAGE=handoff; NOEMIT=$check_only
  read_text "$file"
  local cv id hrole slug label active access writes_line
  scan_handoff
  word1 "$K_CONTRACT"; cv="$W"; word1 "$K_ID"; id="$W"; word1 "$K_ROLE"; hrole="$W"
  XID="$id"; XROLE="$hrole"
  [ -n "$cv" ] || bad missing-field "no CONTRACT: line"
  case "$cv" in *[!0-9]*) bad malformed "CONTRACT: must be a number" ;; esac
  [ "$cv" = "$CV" ] || bad unsupported-version "CONTRACT: $cv (this kit speaks $CV)"
  [ -n "$id" ] || bad missing-field "no ID: line"
  valid_id "$id" || bad bad-value "ID must be <task-slug>/<label> (letters, digits, _ . -)"
  slug="${id%%/*}"; label="${id#*/}"
  active="$(active_task "$task")"
  [ -z "$active" ] || [ "$active" = "$slug" ] || bad task-mismatch "ID names task '$slug', the open task is '$active'"
  [ -n "$hrole" ] || bad missing-field "no ROLE: line"
  [ -z "$role" ] || [ "${role##*:}" = "${hrole}" ] || bad role-mismatch "ROLE: $hrole but the agent being started is '${role##*:}'"
  local base="${hrole%-deep}" rf
  rf="$(role_file "$base")" || bad role-mismatch "unknown role '$hrole'"
  role_meta "$rf"; access="$R_ACCESS"
  [ "$R_KIND" = subagent ] || bad role-mismatch "'$hrole' is not a subagent role"
  [ -n "$K_TASK" ] || bad missing-field "no TASK: line"
  writes_line="$K_SCOPE"; [ -n "$writes_line" ] || bad missing-field "no SCOPE: line"
  case "$writes_line" in writes:*) ;; *) bad bad-value "SCOPE: must start with 'writes:'" ;; esac
  local wl; wl="$(printf '%s' "${writes_line#writes:}" | tr -d ' ')"
  if [ "$access" = read-only ]; then
    [ "$wl" = none ] || bad inconsistent "$hrole is read-only but SCOPE lists writes"
  else
    [ -n "$wl" ] && [ "$wl" != none ] || bad missing-field "$hrole writes files but SCOPE: writes: is none or empty"
  fi
  local p base_dir="$top" wt="$K_WORKTREE"; word1 "$wt"; wt="$W"
  if [ -n "$wt" ]; then [ -d "$wt" ] || bad missing-artifact "WORKTREE $wt is not a directory"; base_dir="$wt"; fi
  if [ "$wl" != none ]; then
    while IFS= read -r p; do p="${p%/}"; safe_rel "$p" || bad unsafe-path "writes: '$p'"; done <<< "$(printf '%s' "$wl" | tr ',' '\n')"
  fi
  while IFS= read -r p; do
    trim "$p"; p="$T"; [ -z "$p" ] && continue
    safe_rel "$p" || bad unsafe-path "READ: '$p'"
    [ -e "$base_dir/$p" ] || bad missing-artifact "READ: '$p' does not exist"
    inside_root "$base_dir" "$p" || bad unsafe-path "READ: '$p' resolves outside the repository"
  done <<< "$(printf '%s' "$K_READ" | tr ',' '\n')"
  local out; word1 "$K_OUT"; out="$W"
  if [ -n "$out" ]; then
    out="${out#"$KIT_DIR"/}"
    safe_rel "$out" || bad unsafe-path "OUT: '$out'"
    case "$out" in work/"$slug"/out/*) ;; *) bad unsafe-path "OUT: must be under work/$slug/out/" ;; esac
  fi
  local retry; word1 "$K_RETRY"; retry="$W"
  if [ -n "$retry" ]; then
    case "$retry" in */*) ;; *) retry="$slug/$retry" ;; esac
    [ "${retry%%/*}" = "$slug" ] || bad task-mismatch "RETRY-OF belongs to another task"
    [ -f "$(reg_file "$slug" "${retry#*/}")" ] || bad unknown-id "RETRY-OF $retry was never issued"
    local rrole rstate; IFS="$US" read -r rrole rstate <<< "$(jq -r --arg u "$US" '[.role, .state] | join($u)' "$(reg_file "$slug" "${retry#*/}")")"
    [ "$rrole" = "$hrole" ] || bad role-mismatch "RETRY-OF $retry was issued to another role"
    case "$rstate" in invalid|interrupted|issued) ;; *) bad bad-value "RETRY-OF $retry is $rstate, only an invalid or interrupted id can be retried" ;; esac
  fi
  if [ "$check_only" = 0 ]; then
    [ -f "$(reg_file "$slug" "$label")" ] && bad duplicate "ID $id was already issued"
    mkdir -p "$(reg_dir "$slug")" 2>/dev/null || bad bad-value "cannot create the registry"
    local f; f="$(reg_file "$slug" "$label")"
    # first writer wins: the file is created exclusively, so two issues of one id cannot both succeed
    ( set -C; : > "$f" ) 2>/dev/null || bad duplicate "ID $id was already issued"
    jq -n --arg id "$id" --arg role "$hrole" --arg access "$access" --arg w "$wl" --arg out "$out" --arg retry "$retry" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson b "$BYTES" --argjson cv "$CV" \
      '{v:$cv, id:$id, role:$role, access:$access, state:"issued", issued:$t, writes:(if $w == "none" then [] else ($w | split(",")) end), out:(if $out == "" then null else $out end), retry_of:(if $retry == "" then null else $retry end), handoff_bytes:$b, result:null, reason:null}' > "$f"
    [ -z "$retry" ] || reg_update "${retry%%/*}" "${retry#*/}" '.state="superseded" | .superseded_by=$n' --arg n "$id" || true
  fi
  tele_ok_handoff
  echo "CONTRACT=valid stage=handoff id=$id role=$hrole"
  exit 0
}
tele_ok_handoff() { [ "${NOEMIT:-0}" = 1 ] || tele valid handoff "$XID" "$XROLE" "" "" "$BYTES" "$SRC"; }

# ---- check-result -------------------------------------------------------------------------------------------------------------------
cmd_check_result() {
  local file="${1:-}"; [ $# -gt 0 ] && shift
  local want_id="" role="" task="" cwd="$top" legacy=0
  RECORD=0
  while [ $# -gt 0 ]; do case "$1" in --id) want_id="$2"; shift ;; --role) role="$2"; shift ;; --task) task="$2"; shift ;; --cwd) cwd="$2"; shift ;; --record) RECORD=1 ;; --legacy-ok) legacy=1 ;; --source) SRC="$2"; shift ;; esac; shift; done
  [ -n "$file" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
  STAGE=result
  read_text "$file"
  role="${role##*:}"; XROLE="$role"; XID="$want_id"
  local marks n=0 l
  marks="$(printf '%s\n' "$TEXT" | awk '{ sub(/^[ \t>`*-]+/, ""); sub(/[ \t`*]+$/, ""); if (index($0, "HANDOFF-RESULT") == 1 && !(($0) in seen)) { seen[$0] = 1; print } }')"
  [ -z "$marks" ] || while IFS= read -r l; do n=$((n + 1)); done <<< "$marks"
  if [ "$n" = 0 ]; then
    if [ "$legacy" = 1 ]; then
      [ -n "$(cmd_pending --role "$role" --task "$task" --quiet)" ] || exit 0   # nothing was waiting for this role: a legacy handoff
    fi
    case "$TEXT" in *[![:space:]]*) bad malformed "no HANDOFF-RESULT line in the answer" ;; *) bad no-result "the agent returned nothing" ;; esac
  fi
  [ "$n" = 1 ] || bad malformed "$n different HANDOFF-RESULT lines (exactly one is allowed)"
  local line="$marks" head rest ver
  head="${line%%|*}"; trim "$head"; head="$T"
  case "$head" in HANDOFF-RESULT/[0-9]*) ver="${head#HANDOFF-RESULT/}" ;; *) bad malformed "first field must be HANDOFF-RESULT/<version>" ;; esac
  case "$ver" in *[!0-9]*) bad malformed "version '$ver' is not a number" ;; esac
  [ "$ver" = "$CV" ] || bad unsupported-version "HANDOFF-RESULT/$ver (this kit speaks $CV)"
  rest="${line#*|}"
  [ "$rest" != "$line" ] || bad missing-field "no fields after the version"
  local id="" rrole="" status="" arts="" blockers="" next="" key val seen=" "
  while IFS= read -r l; do
    trim "$l"; l="$T"
    [ -n "$l" ] || bad malformed "empty field (a '|' inside a value?)"
    key="${l%%:*}"; val="${l#*:}"; trim "$val"; val="$T"
    case "$key" in id|role|status|artifacts|blockers|next) ;; *) bad malformed "unknown or unreadable field: $key" ;; esac
    case "$seen" in *" $key "*) bad malformed "field '$key' appears twice" ;; esac
    seen="$seen$key "
    case "$key" in id) id="$val" ;; role) rrole="$val" ;; status) status="$val" ;; artifacts) arts="$val" ;; blockers) blockers="$val" ;; next) next="$val" ;; esac
  done <<< "$(printf '%s' "$rest" | tr '|' '\n')"
  [ -n "$id" ] || bad missing-field "field 'id' is empty or missing"
  [ -n "$rrole" ] || bad missing-field "field 'role' is empty or missing"
  [ -n "$status" ] || bad missing-field "field 'status' is empty or missing"
  [ -n "$arts" ] || bad missing-field "field 'artifacts' is empty or missing (use: artifacts: none)"
  [ -n "$blockers" ] || bad missing-field "field 'blockers' is empty or missing (use: blockers: none)"
  XID="$id"; XROLE="$rrole"; XSTATUS=""
  valid_id "$id" || bad bad-value "id must be <task-slug>/<label>"
  case "$status" in done|partial|blocked|failed) XSTATUS="$status" ;; *) bad bad-value "status must be done|partial|blocked|failed, got '$status'" ;; esac
  [ "${#blockers}" -le 200 ] && [ "${#next}" -le 200 ] || bad bad-value "blockers and next are limited to 200 characters (put the long form in OUT)"
  local slug="${id%%/*}" label="${id#*/}" active
  [ -z "$want_id" ] || [ "$want_id" = "$id" ] || bad id-mismatch "the answer says id $id, the handoff was $want_id"
  active="$(active_task "$task")"
  [ -z "$active" ] || [ "$active" = "$slug" ] || bad task-mismatch "id names task '$slug', the open task is '$active'"
  [ -z "$role" ] || [ "$role" = "$rrole" ] || bad role-mismatch "the answer says role $rrole, the agent is $role"
  local f; f="$(reg_file "$slug" "$label")"
  [ -f "$f" ] || bad unknown-id "$id was never issued (no registered handoff)"
  local ireg access state sup out writes
  IFS="$US" read -r ireg access state sup out writes <<< "$(jq -r --arg u "$US" '[.role, .access, .state, (.superseded_by // ""), (.out // ""), (.writes | join(","))] | join($u)' "$f")"
  [ "$ireg" = "$rrole" ] || bad role-mismatch "the handoff was issued to $ireg, the answer says $rrole"
  # state: one answer per handoff; an answer to a superseded or interrupted one is stale
  case "$state" in
    accepted) bad duplicate "$id already has an accepted result" ;;
    superseded) bad stale "$id was superseded by $sup" ;;
    interrupted) bad stale "$id was closed as interrupted" ;;
  esac
  if [ "$blockers" = none ]; then
    [ "$status" = done ] || bad inconsistent "status $status needs blockers: <why>"
  else
    [ "$status" != done ] || bad inconsistent "status done with blockers"
  fi
  if [ "$arts" != none ]; then
    [ "$access" != read-only ] || bad inconsistent "$rrole is read-only and cannot produce artifacts (use artifacts: none)"
    local p
    while IFS= read -r p; do
      trim "$p"; p="${T%/}"
      safe_rel "$p" || bad unsafe-path "artifact '$p'"
      [ -e "$cwd/$p" ] || bad missing-artifact "artifact '$p' does not exist"
      inside_root "$cwd" "$p" || bad unsafe-path "artifact '$p' resolves outside the repository"
      in_scope "$p" "$writes" || { [ -n "$out" ] && { [ "$p" = "$out" ] || [ "$p" = "$KIT_DIR/$out" ]; }; } || bad out-of-scope "artifact '$p' is outside the handoff's writes"
    done <<< "$(printf '%s' "$arts" | tr ',' '\n')"
  fi
  if [ "$RECORD" = 1 ]; then
    # check and set under one lock: of several identical answers exactly one is accepted
    sdkit_lock "$f"
    local st; st="$(jq -r '.state' "$f")"
    if [ "$st" = accepted ]; then sdkit_unlock "$f"; bad duplicate "$id already has an accepted result"; fi
    local tmp; tmp="$(mktemp "$f.XXXXXX")"
    jq --arg s "$status" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson b "$BYTES" '.state="accepted" | .reason=null | .result={status:$s, bytes:$b, at:$t}' "$f" > "$tmp" && mv "$tmp" "$f"; rm -f "$tmp"
    sdkit_unlock "$f"
  fi
  tele valid result "$id" "$rrole" "$status" "" "$BYTES" "$SRC"
  echo "CONTRACT=valid stage=result id=$id role=$rrole status=$status"
  [ "$status" = done ]; exit $?
}

# ---- the rest -----------------------------------------------------------------------------------------------------------------------
cmd_pending() {  # ids issued and not answered; --quiet prints bare ids
  local role="" task="" quiet=0
  while [ $# -gt 0 ]; do case "$1" in --role) role="${2##*:}"; shift ;; --task) task="$2"; shift ;; --quiet) quiet=1 ;; esac; shift; done
  local s f; s="$(active_task "$task")"; [ -n "$s" ] || return 0
  valid_part "$s" || return 0
  for f in "$(reg_dir "$s")"/*.json; do
    [ -f "$f" ] || continue
    jq -r --arg r "$role" 'select(.state == "issued" and ($r == "" or .role == $r)) | .id' "$f" 2>/dev/null
  done
  return 0
}
cmd_close() {
  local id="${1:-}"; [ $# -gt 0 ] && shift
  local reason=interrupted task=""
  while [ $# -gt 0 ]; do case "$1" in --reason) reason="$2"; shift ;; --task) task="$2"; shift ;; --source) SRC="$2"; shift ;; esac; shift; done
  case "$id" in */*) ;; *) id="$(active_task "$task")/$id" ;; esac
  valid_id "$id" || { echo "contract: '$id' is not a <task>/<label> id" >&2; exit 2; }
  [ -f "$(reg_file "${id%%/*}" "${id#*/}")" ] || { echo "contract: $id was never issued" >&2; exit 2; }
  reg_update "${id%%/*}" "${id#*/}" 'if .state == "issued" or .state == "invalid" then .state="interrupted" | .reason=$r else . end' --arg r "$reason"
  STAGE=result; XID="$id"; XROLE="$(reg_get "${id%%/*}" "${id#*/}" .role)"; tele invalid result "$id" "$XROLE" "" no-result 0 "${SRC:-contract}"
  echo "CONTRACT=closed id=$id state=$(reg_get "${id%%/*}" "${id#*/}" .state)"
}
cmd_status() {
  local s="${1:-}"; [ -n "$s" ] || s="$(active_task "")"; [ -n "$s" ] || { echo "no open task"; return 0; }
  valid_part "$s" || { echo "contract: '$s' is not a task slug" >&2; exit 2; }
  local f n=0
  for f in "$(reg_dir "$s")"/*.json; do
    [ -f "$f" ] || continue; n=$((n + 1))
    jq -r '"\(.id)  \(.role)  \(.state)\(if .result then "  status=" + .result.status else "" end)\(if .reason then "  reason=" + .reason else "" end)"' "$f"
  done
  [ "$n" -gt 0 ] || echo "no contracts for $s"
}

case "$cmd" in
  issue) cmd_issue "$@" ;;
  check-result) cmd_check_result "$@" ;;
  close) cmd_close "$@" ;;
  pending) cmd_pending "$@" ;;
  status) cmd_status "$@" ;;
  id) read_text "${1:--}"; scan_handoff; word1 "$K_ID"; echo "$W" ;;
  *) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
