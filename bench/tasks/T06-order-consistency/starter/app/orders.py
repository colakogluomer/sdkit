from .payments import PaymentError  # noqa: F401  (re-exported for callers)


class OrderRejected(Exception):
    """The order cannot be placed (unknown SKU or not enough stock)."""


class IdempotencyConflict(Exception):
    """The idempotency key was already used for a different order."""


def place_order(db, payments, idem_key, lines):
    """Reserve stock, charge the customer and record the order.

    `db` is a sqlite3 connection (schema in schema.py), `payments` a gateway with
    charge(amount_cents, idem_key) -> charge_id and refund(charge_id), `lines` a list of
    (sku, qty, price_cents). Returns {"id", "status", "total_cents", "charge_id"}.
    """
    total = 0
    for sku, qty, price in lines:
        db.execute("UPDATE stock SET qty = qty - ? WHERE sku = ?", (qty, sku))
        db.commit()
        total += qty * price
    charge_id = payments.charge(total, idem_key)
    order_id = "ord-" + idem_key
    db.execute(
        "INSERT INTO orders(id, idem_key, fingerprint, total_cents, charge_id, status) VALUES (?, ?, '', ?, ?, 'paid')",
        (order_id, idem_key, total, charge_id),
    )
    for sku, qty, price in lines:
        db.execute("INSERT INTO order_lines VALUES (?, ?, ?, ?)", (order_id, sku, qty, price))
    db.commit()
    return {"id": order_id, "status": "paid", "total_cents": total, "charge_id": charge_id}
