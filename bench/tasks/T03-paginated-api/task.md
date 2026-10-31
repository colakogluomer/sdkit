# Paginate `GET /items` in `app/api.py`

`handle(store, method, path, query)` returns every item at once. Add pagination. Only `app/` may be changed; `tests/` is the visible example suite.
`query` is a dict of strings (already parsed from the URL); unknown parameters are ignored.

1. Parameters: `page` (default 1) and `per_page` (default 20).
2. `page` must be an integer >= 1 and `per_page` an integer from 1 to 100. Decimal ASCII only (no sign, whitespace, or fractions).
   Anything else returns `400` with a body `{"error": <non-empty string>}`. Nothing is paginated in that case.
3. Items are ordered by ascending `id` (the store does not guarantee order), then sliced for the page.
4. A successful body is `{"items": [...], "page": p, "per_page": n, "total": N, "total_pages": T, "links": {"prev": ..., "next": ...}}`.
   `total` is the number of items overall, `total_pages` is `ceil(total / per_page)` (0 when there are no items).
5. `links.next` is `"/items?page=<p+1>&per_page=<n>"` when `p < total_pages`, otherwise `None`.
   `links.prev` is `"/items?page=<p-1>&per_page=<n>"` when `p > 1`, otherwise `None`.
6. A page beyond the last one is not an error: `200` with `items == []` and the page echoed back.
7. Paging through all pages yields every item exactly once, in id order.
8. The 404 and 405 behavior stays as it is.
