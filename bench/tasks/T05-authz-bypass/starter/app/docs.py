from .errors import NotFound, Unauthenticated


class DocService:
    """Documents with owners and per-user sharing.

    `directory` maps user id -> {"id", "role": "user"|"admin", "active": bool}.
    A document is {"id", "owner_id", "title", "body", "shared": {user_id: "read"|"write"}}.
    """

    def __init__(self, directory):
        self._directory = directory
        self._docs = {}
        self._next = 1

    def _actor(self, actor_id):
        user = self._directory.get(actor_id)
        if user is None:
            raise Unauthenticated(actor_id)
        return user

    def create(self, actor_id, title, body):
        self._actor(actor_id)
        doc = {"id": self._next, "owner_id": actor_id, "title": title, "body": body, "shared": {}}
        self._next += 1
        self._docs[doc["id"]] = doc
        return dict(doc)

    def get(self, actor_id, doc_id):
        self._actor(actor_id)
        doc = self._docs.get(doc_id)
        if doc is None:
            raise NotFound(doc_id)
        return dict(doc)

    def list(self, actor_id):
        self._actor(actor_id)
        return [dict(d) for d in sorted(self._docs.values(), key=lambda d: d["id"])]

    def update(self, actor_id, doc_id, changes):
        self._actor(actor_id)
        doc = self._docs.get(doc_id)
        if doc is None:
            raise NotFound(doc_id)
        doc.update(changes)
        return dict(doc)

    def share(self, actor_id, doc_id, target_id, level):
        self._actor(actor_id)
        doc = self._docs.get(doc_id)
        if doc is None:
            raise NotFound(doc_id)
        doc["shared"][target_id] = True
        return dict(doc)

    def delete(self, actor_id, doc_id):
        self._actor(actor_id)
        if self._docs.pop(doc_id, None) is None:
            raise NotFound(doc_id)
