#!/usr/bin/env bash
# Secret redaction filter (F19): stdin -> stdout with credential-shaped strings replaced by [REDACTED:<kind>]. Deterministic patterns only; a filter
# for views and logs, NOT a guarantee that no secret remains (an unknown format passes through), so secrets still must not be written into prompts.
#   kinds: private-key blocks, AWS access key ids, GitHub tokens (ghp_/gho_/ghs_/ghu_/github_pat_), Slack tokens, API keys (sk-…, sk-ant-…),
#          JWTs, "Bearer …", and  password|passwd|secret|token|api_key|api-key = value  assignments (any letter case).
# POSIX awk only (no GNU/BSD sed differences).
set -u
awk '
function rep(s, re, tag,   out, p) {            # replace every match of re in s by tag
  out = ""
  while (match(s, re)) { out = out substr(s, 1, RSTART - 1) tag; s = substr(s, RSTART + RLENGTH) }
  return out s
}
function repci(s, re, keep,   out, low) {       # case-insensitive "word <sep> value" : keep the left part, hide the value
  out = ""
  while (1) {
    low = tolower(s)
    if (!match(low, re)) break
    pre = substr(s, 1, RSTART - 1); hit = substr(s, RSTART, RLENGTH)
    sub(/[^ \t:="\047]+$/, "", hit)
    out = out pre hit "[REDACTED:value]"; s = substr(s, RSTART + RLENGTH)
  }
  return out s
}
/-----BEGIN [A-Z ]*PRIVATE KEY-----/ { inkey = 1 }
inkey { if ($0 ~ /-----END [A-Z ]*PRIVATE KEY-----/) { inkey = 0; print "[REDACTED:private-key]" } ; next }
{
  l = $0
  l = rep(l, "AKIA[0-9A-Z]{16}", "[REDACTED:aws-key-id]")
  l = rep(l, "(ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}", "[REDACTED:github-token]")
  l = rep(l, "github_pat_[A-Za-z0-9_]{20,}", "[REDACTED:github-token]")
  l = rep(l, "xox[abprs]-[A-Za-z0-9-]{10,}", "[REDACTED:slack-token]")
  l = rep(l, "sk-(ant-)?[A-Za-z0-9_-]{16,}", "[REDACTED:api-key]")
  l = rep(l, "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}", "[REDACTED:jwt]")
  # Bearer <token>: keep the word
  out = ""; while (match(l, /[Bb]earer[ \t]+[A-Za-z0-9._~+\/=-]{12,}/)) { hit = substr(l, RSTART, RLENGTH); sub(/[ \t]+[^ \t]+$/, " [REDACTED:bearer]", hit); out = out substr(l, 1, RSTART - 1) hit; l = substr(l, RSTART + RLENGTH) } ; l = out l
  l = repci(l, "(password|passwd|secret|token|api[_-]?key)[ \t]*[:=][ \t]*[\"\047]?[^ \t\"\047]{6,}")
  print l
}' 
