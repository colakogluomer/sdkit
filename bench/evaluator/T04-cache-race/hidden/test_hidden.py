import threading
import time
import unittest

from app.cache import LoadingCache

WAIT = 5.0


def run_threads(n, fn):
    results, errors = [None] * n, [None] * n
    start = threading.Barrier(n)

    def work(i):
        start.wait(WAIT)
        try:
            results[i] = fn(i)
        except BaseException as exc:  # noqa: B902
            errors[i] = exc

    threads = [threading.Thread(target=work, args=(i,), daemon=True) for i in range(n)]
    for t in threads:
        t.start()
    return threads, results, errors


def join(threads):
    for t in threads:
        t.join(WAIT * 2)
        assert not t.is_alive(), "a thread is stuck"


class Concurrency(unittest.TestCase):
    def test_R1_single_flight(self):
        release, calls, lock = threading.Event(), [], threading.Lock()

        def loader(key):
            with lock:
                calls.append(key)
            release.wait(WAIT)
            return "value-" + key

        cache = LoadingCache(loader)
        threads, results, errors = run_threads(8, lambda i: cache.get("k"))
        time.sleep(0.4)
        release.set()
        join(threads)
        self.assertEqual(errors, [None] * 8)
        self.assertEqual(results, ["value-k"] * 8)
        self.assertEqual(calls, ["k"])

    def test_R2_different_keys_in_parallel(self):
        started = {"a": threading.Event(), "b": threading.Event()}

        def loader(key):
            started[key].set()
            other = "b" if key == "a" else "a"
            if not started[other].wait(2.0):
                raise RuntimeError("load of %s was blocked by the load of %s" % (other, key))
            return key

        cache = LoadingCache(loader)
        threads, results, errors = run_threads(2, lambda i: cache.get("ab"[i]))
        join(threads)
        self.assertEqual(errors, [None, None])
        self.assertEqual(results, ["a", "b"])

    def test_R3_error_reaches_all_waiters_and_is_not_cached(self):
        release, calls, lock = threading.Event(), [], threading.Lock()
        boom = ValueError("backend down")

        def loader(key):
            with lock:
                calls.append(key)
                attempt = len(calls)
            if attempt == 1:
                release.wait(WAIT)
                raise boom
            return "ok"

        cache = LoadingCache(loader)
        threads, results, errors = run_threads(6, lambda i: cache.get("k"))
        time.sleep(0.4)
        release.set()
        join(threads)
        self.assertEqual(len(calls), 1)
        self.assertTrue(all(e is boom for e in errors), errors)
        self.assertEqual(cache.get("k"), "ok")
        self.assertEqual(len(calls), 2)

    def test_R3_failure_does_not_affect_other_keys(self):
        def loader(key):
            if key == "bad":
                raise KeyError(key)
            return key

        cache = LoadingCache(loader)
        with self.assertRaises(KeyError):
            cache.get("bad")
        self.assertEqual(cache.get("good"), "good")
        with self.assertRaises(KeyError):
            cache.get("bad")

    def test_R4_ttl_boundary_and_reload_single_flight(self):
        now, calls, lock = [100.0], [], threading.Lock()
        release = threading.Event()

        def loader(key):
            with lock:
                calls.append(key)
                n = len(calls)
            if n > 1:
                release.wait(WAIT)
            return n

        cache = LoadingCache(loader, ttl=5, clock=lambda: now[0])
        self.assertEqual(cache.get("k"), 1)
        now[0] = 104.999
        self.assertEqual(cache.get("k"), 1)
        now[0] = 105.0
        threads, results, errors = run_threads(5, lambda i: cache.get("k"))
        time.sleep(0.4)
        release.set()
        join(threads)
        self.assertEqual(errors, [None] * 5)
        self.assertEqual(results, [2] * 5)
        self.assertEqual(len(calls), 2)

    def test_R5_invalidate_removes_entry(self):
        calls = []
        cache = LoadingCache(lambda k: calls.append(k) or len(calls))
        self.assertEqual(cache.get("k"), 1)
        cache.invalidate("k")
        cache.invalidate("never-loaded")
        self.assertEqual(cache.get("k"), 2)

    def test_R5_invalidate_during_load_discards_result(self):
        entered, release, calls, lock = threading.Event(), threading.Event(), [], threading.Lock()

        def loader(key):
            with lock:
                calls.append(key)
                n = len(calls)
            if n == 1:
                entered.set()
                release.wait(WAIT)
            return n

        cache = LoadingCache(loader)
        threads, results, errors = run_threads(1, lambda i: cache.get("k"))
        self.assertTrue(entered.wait(WAIT))
        cache.invalidate("k")
        release.set()
        join(threads)
        self.assertEqual(results, [1])
        self.assertEqual(cache.get("k"), 2)

    def test_R6_many_keys_many_threads(self):
        calls, lock = {}, threading.Lock()

        def loader(key):
            time.sleep(0.01)
            with lock:
                calls[key] = calls.get(key, 0) + 1
            return key * 2

        cache = LoadingCache(loader)
        threads, results, errors = run_threads(24, lambda i: cache.get(str(i % 4)))
        join(threads)
        self.assertEqual(errors, [None] * 24)
        self.assertEqual(results, [str(i % 4) * 2 for i in range(24)])
        self.assertEqual(calls, {"0": 1, "1": 1, "2": 1, "3": 1})


if __name__ == "__main__":
    unittest.main()
