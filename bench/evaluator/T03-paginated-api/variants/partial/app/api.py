def handle(store, method, path, query=None):
    query = query or {}
    if path != "/items":
        return 404, {"error": "not found"}
    if method != "GET":
        return 405, {"error": "method not allowed"}
    page = int(query.get("page", 1))
    per_page = int(query.get("per_page", 20))
    items = sorted(store.all(), key=lambda item: item["id"])
    total = len(items)
    total_pages = -(-total // per_page)
    start = (page - 1) * per_page
    return 200, {
        "items": items[start:start + per_page],
        "page": page,
        "per_page": per_page,
        "total": total,
        "total_pages": total_pages,
        "links": {"prev": None, "next": None},
    }
