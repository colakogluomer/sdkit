# Make `place_order` consistent across stock, orders and payments (`app/orders.py`)

`place_order` touches three components: the `stock` and `orders` tables (sqlite3) and an external payment gateway. Today a failure part-way
leaves them out of step (stock gone but no order, a charge with no order, double charges on retries). Fix it. Only `app/` may be changed;
`tests/` is the visible example suite. Standard library only. `payments` is any object with `charge(amount_cents, idem_key)` and `refund(charge_id)`
(`charge` may raise `PaymentError`); it does not deduplicate by key itself.

1. Success: stock is decremented, one `orders` row (status `paid`) plus one `order_lines` row per distinct SKU are stored, the customer is charged
   once for the sum of `qty * price_cents`, and the returned dict is `{"id", "status": "paid", "total_cents", "charge_id"}`.
2. Validation: `lines` must be a non-empty list of `(sku, qty, price_cents)` with positive integer `qty` and non-negative integer price,
   otherwise `ValueError` with no side effects. Lines repeating a SKU are merged (quantities added; the prices must match, else `ValueError`).
3. An unknown SKU, or insufficient stock on ANY line, raises `OrderRejected`. Nothing changes: no stock moves for the other lines, no order rows,
   and the gateway is not charged.
4. If `charge` raises (`PaymentError`), the exception propagates, all stock changes are undone, and no order rows exist.
5. If anything fails after a successful charge (for example the database write), the charge is refunded exactly once, stock is restored,
   no order rows remain, and the original exception propagates.
6. Idempotency: calling again with the same `idem_key` and the same lines returns the original order (equal dict) without charging again and
   without decrementing stock again. The same key with different lines raises `IdempotencyConflict` and changes nothing.
   A key whose earlier attempt failed (rules 3 to 5) leaves no trace, so retrying it is a fresh attempt.
7. After any outcome, `sum(charges) - sum(refunds)` equals the total of the stored orders, and stock equals initial stock minus ordered quantities.
