#!/usr/bin/env bash
# Group tasks into parallel waves from their dependencies and write sets.
# Usage: plan-waves.sh <tasks.md>
# Task line:  - [ ] T3 description | role: developer | size: small|medium|large | writes: services/importer/,pkg/x.go | after: T1,T2
# `size:` is optional and only shown in the output (the orchestrator maps it to a model tier, see model-routing.md).
# No wave is larger than MAX_PARALLEL (environment, else sdkit.env, else 3): a bigger wave is split, the rest wait for the next wave.
# A task with no `writes:` is treated as read-only. Two tasks conflict when a write path equals or contains the other's.
# Output: one line per wave, then exit 0. Exit 1 on a dependency cycle or unknown id.
set -eu
[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: plan-waves.sh <tasks.md>" >&2; exit 2; }

max="${MAX_PARALLEL:-}"
if [ -z "$max" ]; then
  top="$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/env.sh" || { echo "sdkit: env.sh is missing next to $(basename "$0"): run sdkit upgrade" >&2; exit 1; }; SDKIT_ENV_QUIET=1 sdkit_env_load "$top"; max="${MAX_PARALLEL:-}"
  fi
fi
case "$max" in ''|*[!0-9]*|0) max=3 ;; esac

awk -v max="$max" '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function label(t,   l) {
  l = role[t] (size[t] != "" ? (role[t] != "" ? "," : "") size[t] : "")
  return l != "" ? "(" l ")" : ""
}
function conflict(a, b,   na, nb, i, j, pa, pb, A, B) {
  na = split(writes[a], A, ","); nb = split(writes[b], B, ",")
  for (i = 1; i <= na; i++) for (j = 1; j <= nb; j++) {
    pa = trim(A[i]); pb = trim(B[j]); if (pa == "" || pb == "") continue
    sub(/\/+$/, "", pa); sub(/\/+$/, "", pb)
    if (pa == pb || index(pa "/", pb "/") == 1 || index(pb "/", pa "/") == 1) return 1
  }
  return 0
}
/^[ \t]*- \[[ xX]\] +[A-Za-z0-9_.-]+/ {
  line = $0; sub(/^[ \t]*- \[[ xX]\] +/, "", line)
  split(line, f, "|"); split(trim(f[1]), h, " "); id = h[1]
  if (id in seen) { print "duplicate task id " id > "/dev/stderr"; bad = 1; next }
  seen[id] = 1; order[++n] = id; writes[id] = ""; after[id] = ""; role[id] = ""; size[id] = ""
  for (k = 2; k in f; k++) {
    kv = trim(f[k])
    if (kv ~ /^writes:/) { sub(/^writes:[ ]*/, "", kv); writes[id] = kv }
    else if (kv ~ /^after:/) { sub(/^after:[ ]*/, "", kv); after[id] = kv }
    else if (kv ~ /^role:/) { sub(/^role:[ ]*/, "", kv); role[id] = kv }
    else if (kv ~ /^size:/) { sub(/^size:[ ]*/, "", kv); size[id] = kv }
  }
}
END {
  if (bad) exit 1
  for (i = 1; i <= n; i++) {
    m = split(after[order[i]], D, ",")
    for (j = 1; j <= m; j++) { d = trim(D[j]); if (d != "" && !(d in seen)) { print order[i] " depends on unknown task " d > "/dev/stderr"; exit 1 } }
  }
  left = n; wave = 0
  while (left > 0) {
    wave++; cnt = 0; line = ""
    for (i = 1; i <= n; i++) {
      t = order[i]; if (t in done) continue
      ready = 1; m = split(after[t], D, ",")
      for (j = 1; j <= m; j++) { d = trim(D[j]); if (d != "" && !(d in done)) ready = 0 }
      if (!ready) continue
      ok = 1
      for (c = 1; c <= cnt; c++) if (conflict(t, pick[c])) ok = 0
      if (ok && cnt < max) { pick[++cnt] = t }
    }
    if (cnt == 0) { print "dependency cycle among remaining tasks" > "/dev/stderr"; exit 1 }
    for (c = 1; c <= cnt; c++) { done[pick[c]] = 1; left--; line = line (c > 1 ? "  ||  " : "") pick[c] label(pick[c]) }
    print "wave " wave ": " line
    for (c = 1; c <= cnt; c++) delete pick[c]
  }
}' "$1"
