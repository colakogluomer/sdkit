. ./store.sh
put k v && [ "$(get k)" = v ] || exit 1
put FAIL x; [ ! -d .lock ] || exit 1
