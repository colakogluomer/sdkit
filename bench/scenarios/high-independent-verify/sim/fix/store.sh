put() { mkdir .lock || return 1; trap "rmdir .lock" RETURN; [ "$1" = FAIL ] && return 1; echo "$2" > ".v.$1"; }
get() { cat ".v.$1"; }
