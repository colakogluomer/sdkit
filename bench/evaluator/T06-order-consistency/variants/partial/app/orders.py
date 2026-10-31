from .payments import PaymentError  # noqa: F401


class OrderRejected(Exception):
    pass


class IdempotencyConflict(Exception):
    pass


def place_order(db, payments, idem_key, lines):
    """Atomic stock reservation, but no idempotency and no refund."""
    total = 0
    try:
        for sku, qty, price in lines:
            cur = db.execute("UPDATE stock SET qty = qty - ? WHERE sku = ? AND qty >= ?", (qty, sku, qty))
            if cur.rowcount != 1:
                raise OrderRejected(sku)
            total += qty * price
        charge_id = payments.charge(total, idem_key)
        order_id = "ord-" + idem_key
        db.execute("INSERT INTO orders(id, idem_key, fingerprint, total_cents, charge_id, status) "
                   "VALUES (?, ?, '', ?, ?, 'paid')", (order_id, idem_key, total, charge_id))
        for sku, qty, price in lines:
            db.execute("INSERT INTO order_lines VALUES (?, ?, ?, ?)", (order_id, sku, qty, price))
        db.commit()
    except BaseException:
        db.rollback()
        raise
    return {"id": order_id, "status": "paid", "total_cents": total, "charge_id": charge_id}
