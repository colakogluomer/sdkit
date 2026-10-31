class InvalidOrderLine(ValueError):
    """An order line that does not follow the SKU:QTY format."""


def parse_order_line(text):
    """Parse 'ABC-1234:5' into {'sku': 'ABC-1234', 'qty': 5}."""
    sku, qty = text.split(":")
    return {"sku": sku, "qty": int(qty)}


def parse_order(text):
    """Parse a comma separated list of order lines into a list of dicts."""
    return [parse_order_line(part) for part in text.split(",")]
