import threading
import time


class _Flight:
    __slots__ = ("event", "value", "error", "valid")

    def __init__(self):
        self.event = threading.Event()
        self.value = None
        self.error = None
        self.valid = True


class LoadingCache:
    """Read-through cache with a time-to-live. `loader(key)` produces a value on a miss."""

    def __init__(self, loader, ttl=60.0, clock=time.monotonic):
        self._loader = loader
        self._ttl = ttl
        self._clock = clock
        self._lock = threading.Lock()
        self._data = {}
        self._flights = {}

    def get(self, key):
        with self._lock:
            entry = self._data.get(key)
            if entry is not None and entry[1] > self._clock():
                return entry[0]
            flight = self._flights.get(key)
            leader = flight is None
            if leader:
                flight = self._flights[key] = _Flight()
        if not leader:
            flight.event.wait()
            if flight.error is not None:
                raise flight.error
            return flight.value
        try:
            value = self._loader(key)
        except BaseException as exc:
            with self._lock:
                if self._flights.get(key) is flight:
                    del self._flights[key]
            flight.error = exc
            flight.event.set()
            raise
        with self._lock:
            if flight.valid:
                self._data[key] = (value, self._clock() + self._ttl)
            if self._flights.get(key) is flight:
                del self._flights[key]
        flight.value = value
        flight.event.set()
        return value

    def invalidate(self, key):
        with self._lock:
            self._data.pop(key, None)
            flight = self._flights.pop(key, None)
            if flight is not None:
                flight.valid = False
