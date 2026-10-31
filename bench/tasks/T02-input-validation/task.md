# Validate order input in `app/orders.py`

`parse_order_line` and `parse_order` accept far too much. Make them strict. Only `app/` may be changed; `tests/` is the visible example suite.
Every rejection raises `InvalidOrderLine` (a `ValueError`); no other exception type may escape for any input.

`parse_order_line(text)`:
1. `text` must be a `str`. Anything else (`None`, `int`, `bytes`) is rejected.
2. The format is exactly `SKU:QTY` with exactly one colon.
3. SKU is three ASCII capital letters, a hyphen, four ASCII digits (`ABC-1234`). No surrounding whitespace, no trailing newline.
4. QTY is a decimal number of ASCII digits without sign, whitespace, underscores, or leading zeros, and between 1 and 1000 inclusive.
   Non-ASCII digits (for example Arabic-Indic) are rejected.
5. Valid input returns `{"sku": ..., "qty": <int>}`.

`parse_order(text)`:
6. Lines are separated by commas; every line is validated by `parse_order_line`. Whitespace around a comma is not tolerated.
7. An empty string, an empty line (including a trailing or doubled comma) is rejected.
8. At most 20 lines. The same SKU may not appear twice.
9. A non-`str` input is rejected.
