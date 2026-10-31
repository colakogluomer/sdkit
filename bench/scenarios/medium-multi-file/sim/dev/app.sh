. "$(dirname "$0")/lib/kv.sh"; . "$(dirname "$0")/lib/upper.sh"
echo "NAME=$(upper "$(kv_value "$1")")"
