import re

DEFAULT_PER_PAGE = 20
MAX_PER_PAGE = 100
_INT = re.compile(r"[0-9]+", re.ASCII)


def _int_param(query, name, default, low, high):
    raw = query.get(name)
    if raw is None:
        return default
    if not isinstance(raw, str) or not _INT.fullmatch(raw):
        raise ValueError("%s must be an integer" % name)
    value = int(raw)
    if value < low or (high is not None and value > high):
        raise ValueError("%s out of range" % name)
    return value


def handle(store, method, path, query=None):
    """Tiny request handler: returns (status, body) where body is a JSON-able dict."""
    query = query or {}
    if path != "/items":
        return 404, {"error": "not found"}
    if method != "GET":
        return 405, {"error": "method not allowed"}
    try:
        page = _int_param(query, "page", 1, 1, None)
        per_page = _int_param(query, "per_page", DEFAULT_PER_PAGE, 1, MAX_PER_PAGE)
    except ValueError as exc:
        return 400, {"error": str(exc)}
    items = sorted(store.all(), key=lambda item: item["id"])
    total = len(items)
    total_pages = -(-total // per_page)
    start = (page - 1) * per_page
    link = "/items?page=%d&per_page=%d"
    return 200, {
        "items": items[start:start + per_page],
        "page": page,
        "per_page": per_page,
        "total": total,
        "total_pages": total_pages,
        "links": {
            "prev": link % (page - 1, per_page) if page > 1 else None,
            "next": link % (page + 1, per_page) if page < total_pages else None,
        },
    }
