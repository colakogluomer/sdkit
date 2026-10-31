import unittest

from app.orders import parse_order, parse_order_line


class PublicTests(unittest.TestCase):
    def test_single_line(self):
        self.assertEqual(parse_order_line("ABC-1234:5"), {"sku": "ABC-1234", "qty": 5})

    def test_two_lines(self):
        self.assertEqual(
            parse_order("ABC-1234:5,XYZ-0001:1"),
            [{"sku": "ABC-1234", "qty": 5}, {"sku": "XYZ-0001", "qty": 1}],
        )


if __name__ == "__main__":
    unittest.main()
