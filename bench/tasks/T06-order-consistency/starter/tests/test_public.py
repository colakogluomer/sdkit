import sqlite3
import unittest

from app.orders import place_order
from app.payments import FakeGateway
from app.schema import init_db


class PublicTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        init_db(self.db)
        self.db.executemany("INSERT INTO stock VALUES (?, ?)", [("AAA-0001", 5), ("BBB-0002", 2)])
        self.db.commit()
        self.pay = FakeGateway()

    def test_happy_path(self):
        order = place_order(self.db, self.pay, "k1", [("AAA-0001", 2, 500), ("BBB-0002", 1, 250)])
        self.assertEqual((order["status"], order["total_cents"]), ("paid", 1250))
        self.assertEqual(self.db.execute("SELECT qty FROM stock WHERE sku='AAA-0001'").fetchone()[0], 3)
        self.assertEqual(list(self.pay.charges.values()), [1250])


if __name__ == "__main__":
    unittest.main()
