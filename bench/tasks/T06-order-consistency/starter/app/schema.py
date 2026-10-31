SCHEMA = """
CREATE TABLE stock (sku TEXT PRIMARY KEY, qty INTEGER NOT NULL CHECK (qty >= 0));
CREATE TABLE orders (
    id TEXT PRIMARY KEY,
    idem_key TEXT NOT NULL UNIQUE,
    fingerprint TEXT NOT NULL,
    total_cents INTEGER NOT NULL,
    charge_id TEXT NOT NULL,
    status TEXT NOT NULL
);
CREATE TABLE order_lines (
    order_id TEXT NOT NULL REFERENCES orders(id),
    sku TEXT NOT NULL,
    qty INTEGER NOT NULL,
    price_cents INTEGER NOT NULL
);
"""


def init_db(db):
    db.executescript(SCHEMA)
    db.commit()
