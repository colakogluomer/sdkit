import re

_SKU = re.compile(r"[A-Z]{3}-[0-9]{4}", re.ASCII)
_QTY = re.compile(r"[1-9][0-9]{0,3}", re.ASCII)
MAX_LINES = 20
MAX_QTY = 1000


class InvalidOrderLine(ValueError):
    """An order line that does not follow the SKU:QTY format."""


def parse_order_line(text):
    """Parse 'ABC-1234:5' into {'sku': 'ABC-1234', 'qty': 5}."""
    if not isinstance(text, str):
        raise InvalidOrderLine("order line must be a string")
    parts = text.split(":")
    if len(parts) != 2:
        raise InvalidOrderLine("expected exactly one ':'")
    sku, qty = parts
    if not _SKU.fullmatch(sku):
        raise InvalidOrderLine("bad SKU")
    if not _QTY.fullmatch(qty) or int(qty) > MAX_QTY:
        raise InvalidOrderLine("bad quantity")
    return {"sku": sku, "qty": int(qty)}


def parse_order(text):
    """Parse a comma separated list of order lines into a list of dicts."""
    if not isinstance(text, str):
        raise InvalidOrderLine("order must be a string")
    parts = text.split(",")
    if len(parts) > MAX_LINES:
        raise InvalidOrderLine("too many lines")
    lines = [parse_order_line(part) for part in parts]
    skus = [line["sku"] for line in lines]
    if len(set(skus)) != len(skus):
        raise InvalidOrderLine("duplicate SKU")
    return lines
