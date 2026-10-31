import sqlite3
import unittest

from app.orders import IdempotencyConflict, OrderRejected, place_order
from app.payments import PaymentError
from app.schema import init_db


class Gateway:
    """Own fake (the one shipped in app/ is not trusted): records every call, never deduplicates."""

    def __init__(self):
        self.charged, self.refunded, self.fail = [], [], 0

    def charge(self, amount_cents, idem_key):
        if self.fail:
            self.fail -= 1
            raise PaymentError("declined")
        self.charged.append((len(self.charged) + 1, amount_cents))
        return "ch-%d" % len(self.charged)

    def refund(self, charge_id):
        self.refunded.append(charge_id)

    def net(self):
        refunded = set(self.refunded)
        return sum(a for n, a in self.charged if "ch-%d" % n not in refunded)


L1, L2 = ("AAA-0001", 2, 500), ("BBB-0002", 1, 250)


class OrderTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        init_db(self.db)
        self.db.executemany("INSERT INTO stock VALUES (?, ?)", [("AAA-0001", 5), ("BBB-0002", 2), ("CCC-0003", 0)])
        self.db.commit()
        self.pay = Gateway()

    def stock(self):
        return dict(self.db.execute("SELECT sku, qty FROM stock").fetchall())

    def counts(self):
        return tuple(self.db.execute("SELECT count(*) FROM %s" % t).fetchone()[0] for t in ("orders", "order_lines"))

    def assert_untouched(self, charges=0):
        self.assertEqual(self.stock(), {"AAA-0001": 5, "BBB-0002": 2, "CCC-0003": 0})
        self.assertEqual(self.counts(), (0, 0))
        self.assertEqual(self.pay.net(), 0)
        self.assertEqual(len(self.pay.charged), charges)

    def test_R1_success(self):
        order = place_order(self.db, self.pay, "k1", [L1, L2])
        self.assertEqual(set(order), {"id", "status", "total_cents", "charge_id"})
        self.assertEqual((order["status"], order["total_cents"]), ("paid", 1250))
        self.assertEqual(self.stock(), {"AAA-0001": 3, "BBB-0002": 1, "CCC-0003": 0})
        self.assertEqual(self.counts(), (1, 2))
        self.assertEqual(self.pay.charged, [(1, 1250)])
        row = self.db.execute("SELECT status, total_cents, charge_id FROM orders WHERE id = ?", (order["id"],)).fetchone()
        self.assertEqual(row, ("paid", 1250, order["charge_id"]))

    def test_R2_validation(self):
        for lines in ([], None, [("AAA-0001", 0, 5)], [("AAA-0001", -1, 5)], [("AAA-0001", 1.5, 5)],
                      [("AAA-0001", 1, -5)], [("AAA-0001", 1, 5.5)], [("AAA-0001", True, 5)],
                      [("AAA-0001", 1, 5), ("AAA-0001", 1, 6)]):
            with self.assertRaises(ValueError, msg=repr(lines)):
                place_order(self.db, self.pay, "kv", lines)
        self.assert_untouched()

    def test_R2_duplicate_skus_merge(self):
        order = place_order(self.db, self.pay, "km", [("AAA-0001", 1, 500), ("AAA-0001", 2, 500)])
        self.assertEqual(order["total_cents"], 1500)
        self.assertEqual(self.stock()["AAA-0001"], 2)
        self.assertEqual(self.counts(), (1, 1))

    def test_R3_insufficient_stock_on_later_line(self):
        with self.assertRaises(OrderRejected):
            place_order(self.db, self.pay, "k2", [L1, ("BBB-0002", 3, 250)])
        self.assert_untouched()

    def test_R3_unknown_sku_and_out_of_stock(self):
        for line in (("ZZZ-9999", 1, 10), ("CCC-0003", 1, 10)):
            with self.assertRaises(OrderRejected):
                place_order(self.db, self.pay, "k3", [L1, line])
            self.assert_untouched()

    def test_R3_exact_stock_is_allowed(self):
        place_order(self.db, self.pay, "k4", [("AAA-0001", 5, 1)])
        self.assertEqual(self.stock()["AAA-0001"], 0)

    def test_R4_payment_declined(self):
        self.pay.fail = 1
        with self.assertRaises(PaymentError):
            place_order(self.db, self.pay, "k5", [L1, L2])
        self.assert_untouched()
        self.assertEqual(place_order(self.db, self.pay, "k5", [L1, L2])["status"], "paid")
        self.assertEqual(self.counts(), (1, 2))

    def test_R5_database_failure_after_charge_refunds_once(self):
        self.db.execute("CREATE TRIGGER no_orders BEFORE INSERT ON orders BEGIN SELECT RAISE(ABORT, 'disk full'); END")
        self.db.commit()
        with self.assertRaises(sqlite3.Error):
            place_order(self.db, self.pay, "k6", [L1, L2])
        self.assertEqual(self.stock(), {"AAA-0001": 5, "BBB-0002": 2, "CCC-0003": 0})
        self.assertEqual(self.counts(), (0, 0))
        self.assertEqual(self.pay.net(), 0)
        self.assertLessEqual(len(self.pay.refunded), 1)
        self.assertEqual(len(self.pay.refunded), len(self.pay.charged))

    def test_R5_line_insert_failure_rolls_back_order_row(self):
        self.db.execute("CREATE TRIGGER no_lines BEFORE INSERT ON order_lines BEGIN SELECT RAISE(ABORT, 'boom'); END")
        self.db.commit()
        with self.assertRaises(sqlite3.Error):
            place_order(self.db, self.pay, "k7", [L1, L2])
        self.assertEqual(self.counts(), (0, 0))
        self.assertEqual(self.stock(), {"AAA-0001": 5, "BBB-0002": 2, "CCC-0003": 0})
        self.assertEqual(self.pay.net(), 0)

    def test_R5_refund_not_called_when_nothing_was_charged(self):
        self.pay.fail = 1
        with self.assertRaises(PaymentError):
            place_order(self.db, self.pay, "k8", [L1])
        self.assertEqual(self.pay.refunded, [])

    def test_R6_idempotent_replay(self):
        first = place_order(self.db, self.pay, "k9", [L1, L2])
        again = place_order(self.db, self.pay, "k9", [L2, L1])
        self.assertEqual(first, again)
        self.assertEqual(len(self.pay.charged), 1)
        self.assertEqual(self.stock(), {"AAA-0001": 3, "BBB-0002": 1, "CCC-0003": 0})
        self.assertEqual(self.counts(), (1, 2))

    def test_R6_key_reuse_with_other_lines(self):
        place_order(self.db, self.pay, "k10", [L1])
        with self.assertRaises(IdempotencyConflict):
            place_order(self.db, self.pay, "k10", [L1, L2])
        with self.assertRaises(IdempotencyConflict):
            place_order(self.db, self.pay, "k10", [("AAA-0001", 2, 501)])
        self.assertEqual(len(self.pay.charged), 1)
        self.assertEqual(self.stock()["AAA-0001"], 3)

    def test_R6_independent_keys_are_independent(self):
        place_order(self.db, self.pay, "ka", [("AAA-0001", 1, 100)])
        place_order(self.db, self.pay, "kb", [("AAA-0001", 1, 100)])
        self.assertEqual(self.stock()["AAA-0001"], 3)
        self.assertEqual(self.counts(), (2, 2))

    def test_R7_ledger_balances_after_mixed_outcomes(self):
        place_order(self.db, self.pay, "m1", [L1])
        with self.assertRaises(OrderRejected):
            place_order(self.db, self.pay, "m2", [("BBB-0002", 9, 1)])
        self.pay.fail = 1
        with self.assertRaises(PaymentError):
            place_order(self.db, self.pay, "m3", [L2])
        place_order(self.db, self.pay, "m1", [L1])
        place_order(self.db, self.pay, "m3", [L2])
        stored = self.db.execute("SELECT coalesce(sum(total_cents), 0) FROM orders").fetchone()[0]
        self.assertEqual(self.pay.net(), stored)
        self.assertEqual(self.stock(), {"AAA-0001": 3, "BBB-0002": 1, "CCC-0003": 0})


if __name__ == "__main__":
    unittest.main()
