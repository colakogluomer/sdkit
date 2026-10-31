class PaymentError(Exception):
    """The payment provider declined or could not be reached."""


class FakeGateway:
    """Stand-in payment provider for tests. It does NOT deduplicate: every charge() call charges again."""

    def __init__(self):
        self.charges = {}
        self.refunded = []
        self.fail_next = 0
        self._n = 0

    def charge(self, amount_cents, idem_key):
        if self.fail_next:
            self.fail_next -= 1
            raise PaymentError("declined")
        self._n += 1
        charge_id = "ch-%d" % self._n
        self.charges[charge_id] = amount_cents
        return charge_id

    def refund(self, charge_id):
        self.refunded.append(charge_id)
