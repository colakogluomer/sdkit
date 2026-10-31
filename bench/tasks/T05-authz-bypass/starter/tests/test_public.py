import unittest

from app.docs import DocService
from app.errors import NotFound, Unauthenticated

USERS = {
    1: {"id": 1, "role": "user", "active": True},
    2: {"id": 2, "role": "user", "active": True},
}


class PublicTests(unittest.TestCase):
    def setUp(self):
        self.svc = DocService(dict(USERS))

    def test_owner_round_trip(self):
        doc = self.svc.create(1, "t", "b")
        self.assertEqual(self.svc.get(1, doc["id"])["title"], "t")
        self.assertEqual(self.svc.update(1, doc["id"], {"body": "c"})["body"], "c")
        self.assertEqual([d["id"] for d in self.svc.list(1)], [doc["id"]])

    def test_unknown_actor(self):
        with self.assertRaises(Unauthenticated):
            self.svc.create(99, "t", "b")

    def test_missing_document(self):
        with self.assertRaises(NotFound):
            self.svc.get(1, 12345)


if __name__ == "__main__":
    unittest.main()
