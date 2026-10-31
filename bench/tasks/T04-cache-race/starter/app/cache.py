import time


class LoadingCache:
    """Read-through cache with a time-to-live. `loader(key)` produces a value on a miss."""

    def __init__(self, loader, ttl=60.0, clock=time.monotonic):
        self._loader = loader
        self._ttl = ttl
        self._clock = clock
        self._data = {}

    def get(self, key):
        entry = self._data.get(key)
        now = self._clock()
        if entry is not None and entry[1] > now:
            return entry[0]
        value = self._loader(key)
        self._data[key] = (value, now + self._ttl)
        return value

    def invalidate(self, key):
        self._data.pop(key, None)
