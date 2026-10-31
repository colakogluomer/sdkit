import unittest

from app.errors import ServiceError, UserNotFound
from app.users import display_name, load_display_name


class Repo:
    def __init__(self, users=None, error=None):
        self.users, self.error, self.calls = users or {}, error, 0

    def get(self, user_id):
        self.calls += 1
        if self.error is not None:
            raise self.error
        return self.users.get(user_id)


class DisplayName(unittest.TestCase):
    def test_R1_full_name_stripped(self):
        self.assertEqual(display_name({"username": "u", "profile": {"full_name": "  Ada  "}}), "Ada")

    def test_R2_profile_none(self):
        self.assertEqual(display_name({"username": " bob ", "profile": None}), "bob")

    def test_R2_profile_missing(self):
        self.assertEqual(display_name({"username": "bob"}), "bob")

    def test_R2_full_name_none(self):
        self.assertEqual(display_name({"username": "bob", "profile": {"full_name": None}}), "bob")

    def test_R2_full_name_blank(self):
        self.assertEqual(display_name({"username": "bob", "profile": {"full_name": "   "}}), "bob")

    def test_R2_full_name_not_a_string(self):
        self.assertEqual(display_name({"username": "bob", "profile": {"full_name": 42}}), "bob")

    def test_R3_no_usable_username(self):
        self.assertEqual(display_name({"profile": None}), "Unknown user")
        self.assertEqual(display_name({"username": None}), "Unknown user")
        self.assertEqual(display_name({"username": "  "}), "Unknown user")

    def test_R3_none_user(self):
        self.assertEqual(display_name(None), "Unknown user")


class Load(unittest.TestCase):
    def test_R4_none_id(self):
        repo = Repo({1: {"username": "a"}})
        with self.assertRaises(ValueError):
            load_display_name(repo, None)
        self.assertEqual(repo.calls, 0)

    def test_R5_missing_user(self):
        with self.assertRaises(UserNotFound):
            load_display_name(Repo(), 7)

    def test_R6_repo_error_wrapped(self):
        boom = ConnectionError("db down")
        with self.assertRaises(ServiceError) as ctx:
            load_display_name(Repo(error=boom), 1)
        self.assertIs(ctx.exception.__cause__, boom)
        self.assertNotIsInstance(ctx.exception, UserNotFound)

    def test_R6_programming_error_not_swallowed(self):
        with self.assertRaises(ServiceError):
            load_display_name(Repo(error=KeyError("x")), 1)

    def test_R7_user_not_found_passes_through(self):
        original = UserNotFound(9)
        with self.assertRaises(UserNotFound) as ctx:
            load_display_name(Repo(error=original), 9)
        self.assertIs(ctx.exception, original)

    def test_R8_incomplete_record_still_loads(self):
        self.assertEqual(load_display_name(Repo({1: {"username": "cy", "profile": None}}), 1), "cy")
        self.assertEqual(load_display_name(Repo({1: {"profile": {}}}), 1), "Unknown user")


if __name__ == "__main__":
    unittest.main()
