import unittest

from app.cache import LoadingCache


class PublicTests(unittest.TestCase):
    def test_hit_does_not_reload(self):
        calls = []
        cache = LoadingCache(lambda k: calls.append(k) or k.upper())
        self.assertEqual(cache.get("a"), "A")
        self.assertEqual(cache.get("a"), "A")
        self.assertEqual(calls, ["a"])

    def test_ttl_expiry(self):
        now = [0.0]
        calls = []
        cache = LoadingCache(lambda k: calls.append(k) or len(calls), ttl=10, clock=lambda: now[0])
        self.assertEqual(cache.get("a"), 1)
        now[0] = 9.9
        self.assertEqual(cache.get("a"), 1)
        now[0] = 10.0
        self.assertEqual(cache.get("a"), 2)


if __name__ == "__main__":
    unittest.main()
