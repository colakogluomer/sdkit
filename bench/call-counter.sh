# BASH_ENV file for `bench/run.sh workflow`: every bash script that starts appends its name to $SDKIT_CALLS (counts script launches, not subshells).
# ($0 is still "bash" while BASH_ENV is read, so the command line is looked up.)
if [ -n "${SDKIT_CALLS:-}" ]; then
  _c="$(ps -o command= -p $$ 2>/dev/null)"; _c="${_c#* }"; _c="${_c%% *}"
  case "${_c##*/}" in *.sh) printf '%s\n' "${_c##*/}" >> "$SDKIT_CALLS" ;; esac
  unset _c
fi
