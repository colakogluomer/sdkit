import re

_SKU = re.compile(r"^[A-Z]{3}-[0-9]{4}$")


class InvalidOrderLine(ValueError):
    pass


def parse_order_line(text):
    sku, qty = text.split(":")
    if not _SKU.match(sku):
        raise InvalidOrderLine("bad SKU")
    try:
        return {"sku": sku, "qty": int(qty)}
    except ValueError:
        raise InvalidOrderLine("bad quantity")


def parse_order(text):
    return [parse_order_line(part) for part in text.split(",")]
