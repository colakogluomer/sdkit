import unittest

from app.api import handle
from app.store import ItemStore


def make(n, shuffled=True):
    ids = list(range(1, n + 1))
    if shuffled:
        ids = ids[1::2][::-1] + ids[0::2]
    return ItemStore({"id": i, "name": "item-%d" % i} for i in ids)


class Pagination(unittest.TestCase):
    def get(self, store, **q):
        return handle(store, "GET", "/items", q)

    def test_R1_defaults(self):
        status, body = self.get(make(45))
        self.assertEqual(status, 200)
        self.assertEqual((body["page"], body["per_page"], body["total"], body["total_pages"]), (1, 20, 45, 3))
        self.assertEqual([i["id"] for i in body["items"]], list(range(1, 21)))

    def test_R2_invalid_values(self):
        s = make(5)
        for q in ({"page": "0"}, {"page": "-1"}, {"page": "abc"}, {"page": ""}, {"page": "1.5"}, {"page": " 2"},
                  {"page": "+1"}, {"per_page": "0"}, {"per_page": "101"}, {"per_page": "x"}, {"per_page": "-5"},
                  {"page": "١"}, {"per_page": "1e1"}):
            status, body = self.get(s, **q)
            self.assertEqual(status, 400, q)
            self.assertTrue(isinstance(body.get("error"), str) and body["error"], q)
            self.assertNotIn("items", body)

    def test_R2_bounds_ok(self):
        self.assertEqual(self.get(make(150), per_page="100")[1]["per_page"], 100)
        self.assertEqual(len(self.get(make(150), per_page="100")[1]["items"]), 100)
        self.assertEqual(len(self.get(make(3), per_page="1")[1]["items"]), 1)

    def test_R3_ordered_by_id(self):
        _, body = self.get(make(10), per_page="4", page="2")
        self.assertEqual([i["id"] for i in body["items"]], [5, 6, 7, 8])

    def test_R4_shape_and_totals(self):
        _, body = self.get(make(10), per_page="4", page="3")
        self.assertEqual(set(body), {"items", "page", "per_page", "total", "total_pages", "links"})
        self.assertEqual((body["total"], body["total_pages"]), (10, 3))
        self.assertEqual([i["id"] for i in body["items"]], [9, 10])

    def test_R4_empty_store(self):
        status, body = self.get(make(0))
        self.assertEqual(status, 200)
        self.assertEqual((body["items"], body["total"], body["total_pages"]), ([], 0, 0))
        self.assertEqual(body["links"], {"prev": None, "next": None})

    def test_R4_exact_multiple(self):
        _, body = self.get(make(40), per_page="20", page="2")
        self.assertEqual(body["total_pages"], 2)
        self.assertIsNone(body["links"]["next"])

    def test_R5_links(self):
        s = make(10)
        _, first = self.get(s, per_page="4")
        self.assertEqual(first["links"], {"prev": None, "next": "/items?page=2&per_page=4"})
        _, mid = self.get(s, per_page="4", page="2")
        self.assertEqual(mid["links"], {"prev": "/items?page=1&per_page=4", "next": "/items?page=3&per_page=4"})
        _, last = self.get(s, per_page="4", page="3")
        self.assertEqual(last["links"], {"prev": "/items?page=2&per_page=4", "next": None})

    def test_R6_page_beyond_last(self):
        status, body = self.get(make(10), per_page="4", page="9")
        self.assertEqual(status, 200)
        self.assertEqual((body["items"], body["page"], body["total"]), ([], 9, 10))
        self.assertIsNone(body["links"]["next"])

    def test_R7_every_item_once(self):
        s = make(47)
        seen, page = [], 1
        while page <= 10:
            _, body = self.get(s, page=str(page), per_page="10")
            if not body["items"]:
                break
            seen += [i["id"] for i in body["items"]]
            page += 1
        self.assertEqual(seen, list(range(1, 48)))

    def test_R7_unknown_params_ignored(self):
        status, body = self.get(make(3), sort="name", page="1")
        self.assertEqual((status, len(body["items"])), (200, 3))

    def test_R8_other_statuses(self):
        s = make(3)
        self.assertEqual(handle(s, "GET", "/other", {})[0], 404)
        self.assertEqual(handle(s, "DELETE", "/items", {})[0], 405)
        self.assertEqual(handle(s, "GET", "/items")[0], 200)


if __name__ == "__main__":
    unittest.main()
