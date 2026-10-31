put() { mkdir .lock || return 1; [ "$1" = FAIL ] && { rmdir .lock; return 1; }; echo "$2" > ".v.$1" || return 1; rmdir .lock; }
get() { cat ".v.$1"; }
