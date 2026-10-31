import threading
import time


class LoadingCache:
    """One global lock: single flight, but loads of different keys serialize."""

    def __init__(self, loader, ttl=60.0, clock=time.monotonic):
        self._loader = loader
        self._ttl = ttl
        self._clock = clock
        self._data = {}
        self._lock = threading.Lock()

    def get(self, key):
        with self._lock:
            entry = self._data.get(key)
            now = self._clock()
            if entry is not None and entry[1] > now:
                return entry[0]
            value = self._loader(key)
            self._data[key] = (value, now + self._ttl)
            return value

    def invalidate(self, key):
        with self._lock:
            self._data.pop(key, None)
