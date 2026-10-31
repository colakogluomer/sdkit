import unittest

from app.orders import InvalidOrderLine, parse_order, parse_order_line


class Line(unittest.TestCase):
    def bad(self, value):
        with self.assertRaises(InvalidOrderLine, msg=repr(value)):
            parse_order_line(value)

    def test_R1_non_strings(self):
        for v in (None, 5, b"ABC-1234:1", ["ABC-1234:1"]):
            self.bad(v)

    def test_R2_colon_count(self):
        for v in ("ABC-1234", "ABC-1234:1:2", ":", "", ":1", "ABC-1234:"):
            self.bad(v)

    def test_R3_sku_format(self):
        for v in ("abc-1234:1", "AB-1234:1", "ABCD-1234:1", "ABC-123:1", "ABC-12345:1", "ABC1234:1",
                  " ABC-1234:1", "ABC-1234 :1", "ABC-1234\n:1", "ÄBC-1234:1", "ABC-١٢٣٤:1"):
            self.bad(v)

    def test_R4_quantity_format(self):
        for v in ("ABC-1234:0", "ABC-1234:-1", "ABC-1234:+5", "ABC-1234: 5", "ABC-1234:5 ", "ABC-1234:5\n",
                  "ABC-1234:1_0", "ABC-1234:05", "ABC-1234:1.0", "ABC-1234:1e2", "ABC-1234:٣", "ABC-1234:0x10"):
            self.bad(v)

    def test_R4_quantity_bounds(self):
        self.assertEqual(parse_order_line("ABC-1234:1000")["qty"], 1000)
        self.assertEqual(parse_order_line("ABC-1234:1")["qty"], 1)
        self.bad("ABC-1234:1001")
        self.bad("ABC-1234:99999999999999999999")

    def test_R5_valid(self):
        self.assertEqual(parse_order_line("QRS-0042:17"), {"sku": "QRS-0042", "qty": 17})
        self.assertIs(type(parse_order_line("QRS-0042:17")["qty"]), int)


class Order(unittest.TestCase):
    def bad(self, value):
        with self.assertRaises(InvalidOrderLine, msg=repr(value)):
            parse_order(value)

    def test_R6_valid_list(self):
        self.assertEqual(parse_order("AAA-0001:1,BBB-0002:2"),
                         [{"sku": "AAA-0001", "qty": 1}, {"sku": "BBB-0002", "qty": 2}])

    def test_R6_whitespace_not_tolerated(self):
        self.bad("AAA-0001:1, BBB-0002:2")
        self.bad("AAA-0001:1 ,BBB-0002:2")

    def test_R6_bad_line_rejects_all(self):
        self.bad("AAA-0001:1,BBB-0002:0")

    def test_R7_empty(self):
        for v in ("", ",", "AAA-0001:1,", ",AAA-0001:1", "AAA-0001:1,,BBB-0002:2"):
            self.bad(v)

    def test_R8_limits(self):
        ok = ",".join("%s-0001:1" % (chr(65 + i // 26) + chr(65 + i % 26) + "X") for i in range(20))
        self.assertEqual(len(parse_order(ok)), 20)
        too_many = ok + ",ZZZ-0001:1"
        self.bad(too_many)

    def test_R8_duplicate_sku(self):
        self.bad("AAA-0001:1,BBB-0002:2,AAA-0001:3")

    def test_R9_non_string(self):
        for v in (None, 1, ["AAA-0001:1"], b"AAA-0001:1"):
            self.bad(v)


if __name__ == "__main__":
    unittest.main()
