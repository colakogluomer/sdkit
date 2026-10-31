import unittest

from app.users import display_name, load_display_name


class Repo:
    def __init__(self, users):
        self.users = users

    def get(self, user_id):
        return self.users.get(user_id)


class PublicTests(unittest.TestCase):
    def test_full_name_is_used(self):
        user = {"username": "ada", "profile": {"full_name": " Ada Lovelace "}}
        self.assertEqual(display_name(user), "Ada Lovelace")

    def test_load_existing_user(self):
        repo = Repo({1: {"username": "ada", "profile": {"full_name": "Ada"}}})
        self.assertEqual(load_display_name(repo, 1), "Ada")


if __name__ == "__main__":
    unittest.main()
