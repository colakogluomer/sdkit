import unittest

from app.docs import DocService
from app.errors import Forbidden, NotFound, Unauthenticated


def users():
    return {
        1: {"id": 1, "role": "user", "active": True},
        2: {"id": 2, "role": "user", "active": True},
        3: {"id": 3, "role": "user", "active": True},
        4: {"id": 4, "role": "admin", "active": True},
        5: {"id": 5, "role": "user", "active": False},
        6: {"id": 6, "role": "admin", "active": False},
    }


class Base(unittest.TestCase):
    def setUp(self):
        self.svc = DocService(users())
        self.doc = self.svc.create(1, "title", "body")["id"]
        self.svc.share(1, self.doc, 2, "read")


class Identity(Base):
    def test_R1_inactive_and_unknown(self):
        for actor in (5, 6, 99, None):
            for call in (lambda a: self.svc.get(a, self.doc), lambda a: self.svc.list(a),
                         lambda a: self.svc.create(a, "t", "b"), lambda a: self.svc.update(a, self.doc, {"body": "x"}),
                         lambda a: self.svc.share(a, self.doc, 3, "read"), lambda a: self.svc.delete(a, self.doc)):
                with self.assertRaises(Unauthenticated):
                    call(actor)

    def test_R1_checked_before_existence(self):
        with self.assertRaises(Unauthenticated):
            self.svc.get(99, 424242)

    def test_R1_deactivated_later(self):
        directory = users()
        svc = DocService(directory)
        d = svc.create(1, "t", "b")["id"]
        directory[1]["active"] = False
        with self.assertRaises(Unauthenticated):
            svc.get(1, d)


class Visibility(Base):
    def test_R2_who_sees_what(self):
        self.assertEqual(self.svc.get(1, self.doc)["id"], self.doc)
        self.assertEqual(self.svc.get(2, self.doc)["id"], self.doc)
        self.assertEqual(self.svc.get(4, self.doc)["id"], self.doc)

    def test_R3_invisible_looks_missing(self):
        with self.assertRaises(NotFound):
            self.svc.get(3, self.doc)
        with self.assertRaises(NotFound):
            self.svc.get(3, 999)

    def test_R3_list_is_filtered_and_ordered(self):
        b = self.svc.create(3, "b", "b")["id"]
        c = self.svc.create(1, "c", "c")["id"]
        self.assertEqual([d["id"] for d in self.svc.list(1)], [self.doc, c])
        self.assertEqual([d["id"] for d in self.svc.list(2)], [self.doc])
        self.assertEqual([d["id"] for d in self.svc.list(3)], [b])
        self.assertEqual([d["id"] for d in self.svc.list(4)], [self.doc, b, c])

    def test_R3_returned_copies_are_detached(self):
        got = self.svc.get(1, self.doc)
        got["shared"][3] = "write"
        got["title"] = "hacked"
        self.assertNotIn(3, self.svc.get(1, self.doc)["shared"])
        self.assertEqual(self.svc.get(1, self.doc)["title"], "title")
        with self.assertRaises(NotFound):
            self.svc.get(3, self.doc)


class Update(Base):
    def test_R4_owner_and_writer(self):
        self.assertEqual(self.svc.update(1, self.doc, {"title": "t2"})["title"], "t2")
        self.svc.share(1, self.doc, 3, "write")
        self.assertEqual(self.svc.update(3, self.doc, {"body": "b2"})["body"], "b2")

    def test_R4_reader_and_admin_forbidden(self):
        for actor in (2, 4):
            with self.assertRaises(Forbidden):
                self.svc.update(actor, self.doc, {"body": "x"})
        self.assertEqual(self.svc.get(1, self.doc)["body"], "body")

    def test_R4_stranger_not_found(self):
        with self.assertRaises(NotFound):
            self.svc.update(3, self.doc, {"body": "x"})

    def test_R5_protected_fields(self):
        for changes in ({"owner_id": 3}, {"id": 77}, {"shared": {3: "write"}}, {"extra": 1}):
            with self.assertRaises(ValueError):
                self.svc.update(1, self.doc, changes)
        stored = self.svc.get(1, self.doc)
        self.assertEqual((stored["owner_id"], stored["id"], stored["shared"]), (1, self.doc, {2: "read"}))

    def test_R5_no_partial_application(self):
        with self.assertRaises(ValueError):
            self.svc.update(1, self.doc, {"title": "new", "owner_id": 3})
        self.assertEqual(self.svc.get(1, self.doc)["title"], "title")

    def test_R5_writer_cannot_take_ownership(self):
        self.svc.share(1, self.doc, 3, "write")
        with self.assertRaises(ValueError):
            self.svc.update(3, self.doc, {"owner_id": 3})
        with self.assertRaises(Forbidden):
            self.svc.share(3, self.doc, 3, "read")

    def test_R8_order_of_checks(self):
        with self.assertRaises(NotFound):
            self.svc.update(3, self.doc, {"owner_id": 3})
        with self.assertRaises(Forbidden):
            self.svc.update(2, self.doc, {"owner_id": 3})


class Share(Base):
    def test_R6_owner_only(self):
        self.svc.share(1, self.doc, 3, "write")
        with self.assertRaises(Forbidden):
            self.svc.share(2, self.doc, 3, "read")
        with self.assertRaises(Forbidden):
            self.svc.share(3, self.doc, 2, "write")
        with self.assertRaises(Forbidden):
            self.svc.share(4, self.doc, 3, "read")

    def test_R6_stranger_not_found(self):
        with self.assertRaises(NotFound):
            self.svc.share(3, self.doc, 3, "write")

    def test_R6_levels_and_targets(self):
        for level in ("admin", "", None, True, "READ"):
            with self.assertRaises(ValueError):
                self.svc.share(1, self.doc, 3, level)
        for target in (99, 5, 6, None):
            with self.assertRaises(ValueError):
                self.svc.share(1, self.doc, target, "read")
        with self.assertRaises(ValueError):
            self.svc.share(1, self.doc, 1, "write")
        self.assertEqual(self.svc.get(1, self.doc)["shared"], {2: "read"})

    def test_R6_replace_level(self):
        self.svc.share(1, self.doc, 2, "write")
        self.assertEqual(self.svc.update(2, self.doc, {"body": "w"})["body"], "w")
        self.svc.share(1, self.doc, 2, "read")
        with self.assertRaises(Forbidden):
            self.svc.update(2, self.doc, {"body": "again"})
        self.assertEqual(self.svc.get(1, self.doc)["shared"], {2: "read"})


class Delete(Base):
    def test_R7_owner_and_admin(self):
        other = self.svc.create(1, "x", "x")["id"]
        self.svc.delete(1, other)
        self.svc.delete(4, self.doc)
        with self.assertRaises(NotFound):
            self.svc.get(1, self.doc)

    def test_R7_reader_writer_forbidden(self):
        self.svc.share(1, self.doc, 3, "write")
        for actor in (2, 3):
            with self.assertRaises(Forbidden):
                self.svc.delete(actor, self.doc)
        self.assertEqual(self.svc.get(1, self.doc)["id"], self.doc)

    def test_R7_stranger_not_found(self):
        d = self.svc.create(1, "private", "p")["id"]
        with self.assertRaises(NotFound):
            self.svc.delete(3, d)
        self.assertEqual(self.svc.get(1, d)["id"], d)


if __name__ == "__main__":
    unittest.main()
