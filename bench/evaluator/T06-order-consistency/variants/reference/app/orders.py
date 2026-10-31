import json

from .payments import PaymentError  # noqa: F401  (re-exported for callers)


class OrderRejected(Exception):
    """The order cannot be placed (unknown SKU or not enough stock)."""


class IdempotencyConflict(Exception):
    """The idempotency key was already used for a different order."""


def _normalize(lines):
    if not isinstance(lines, (list, tuple)) or not lines:
        raise ValueError("lines must be a non-empty list")
    merged = {}
    for line in lines:
        sku, qty, price = line
        for number in (qty, price):
            if type(number) is not int:
                raise ValueError("qty and price must be integers")
        if qty <= 0 or price < 0:
            raise ValueError("qty must be positive and price non-negative")
        if sku in merged and merged[sku][1] != price:
            raise ValueError("conflicting prices for " + str(sku))
        merged[sku] = (merged[sku][0] + qty if sku in merged else qty, price)
    return sorted((sku, qty, price) for sku, (qty, price) in merged.items())


def _result(row):
    return {"id": row[0], "status": row[1], "total_cents": row[2], "charge_id": row[3]}


def place_order(db, payments, idem_key, lines):
    """Reserve stock, charge the customer and record the order.

    `db` is a sqlite3 connection (schema in schema.py), `payments` a gateway with
    charge(amount_cents, idem_key) -> charge_id and refund(charge_id), `lines` a list of
    (sku, qty, price_cents). Returns {"id", "status", "total_cents", "charge_id"}.
    """
    items = _normalize(lines)
    fingerprint = json.dumps(items)
    row = db.execute("SELECT id, status, total_cents, charge_id, fingerprint FROM orders WHERE idem_key = ?",
                     (idem_key,)).fetchone()
    if row is not None:
        if row[4] != fingerprint:
            raise IdempotencyConflict(idem_key)
        return _result(row)
    total = sum(qty * price for _, qty, price in items)
    charge_id = None
    try:
        for sku, qty, _ in items:
            cur = db.execute("UPDATE stock SET qty = qty - ? WHERE sku = ? AND qty >= ?", (qty, sku, qty))
            if cur.rowcount != 1:
                raise OrderRejected(sku)
        charge_id = payments.charge(total, idem_key)
        order_id = "ord-" + idem_key
        db.execute("INSERT INTO orders(id, idem_key, fingerprint, total_cents, charge_id, status) "
                   "VALUES (?, ?, ?, ?, ?, 'paid')", (order_id, idem_key, fingerprint, total, charge_id))
        db.executemany("INSERT INTO order_lines VALUES (?, ?, ?, ?)", [(order_id, s, q, p) for s, q, p in items])
        db.commit()
    except BaseException:
        db.rollback()
        if charge_id is not None:
            payments.refund(charge_id)
        raise
    return {"id": order_id, "status": "paid", "total_cents": total, "charge_id": charge_id}
