# Make `LoadingCache` safe for concurrent use (`app/cache.py`)

Many threads call `LoadingCache.get` at once and the loader (a slow database call) runs many times for the same key. Fix it.
Only `app/` may be changed; `tests/` is the visible example suite. Keep the constructor and method signatures. Standard library only.

1. Single flight: concurrent `get(key)` calls for a key that is not cached run the loader exactly once; every caller receives that value.
2. No global serialization: loads of different keys run concurrently. A slow load of one key must never block a load of another key.
3. Errors: if the loader raises, every caller waiting on that load receives that same exception. Nothing is cached; the next `get` calls the loader again.
4. TTL: an entry is valid while `clock() < stored_at + ttl` (expired exactly at the boundary), using the injected `clock`. An expired entry is reloaded (again single flight).
5. `invalidate(key)` removes a cached entry. If a load of that key is in flight, its callers still receive the value, but the value is not stored,
   so the next `get` loads again.
6. The cache never returns a value after a failed load of a different key, and a failure of one key does not affect other keys.
