def handle(store, method, path, query=None):
    """Tiny request handler: returns (status, body) where body is a JSON-able dict."""
    query = query or {}
    if path != "/items":
        return 404, {"error": "not found"}
    if method != "GET":
        return 405, {"error": "method not allowed"}
    items = store.all()
    return 200, {"items": items}
