import unittest

from app.api import handle
from app.store import ItemStore


class PublicTests(unittest.TestCase):
    def setUp(self):
        self.store = ItemStore({"id": i, "name": "item-%d" % i} for i in range(1, 6))

    def test_list_returns_items(self):
        status, body = handle(self.store, "GET", "/items")
        self.assertEqual(status, 200)
        self.assertEqual(body["items"][0], {"id": 1, "name": "item-1"})

    def test_unknown_path(self):
        self.assertEqual(handle(self.store, "GET", "/nope")[0], 404)

    def test_wrong_method(self):
        self.assertEqual(handle(self.store, "POST", "/items")[0], 405)


if __name__ == "__main__":
    unittest.main()
