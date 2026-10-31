from .errors import NotFound, Unauthenticated


class DocService:
    def __init__(self, directory):
        self._directory = directory
        self._docs = {}
        self._next = 1

    def _actor(self, actor_id):
        user = self._directory.get(actor_id)
        if user is None or not user.get("active"):
            raise Unauthenticated(actor_id)
        return user

    def _visible(self, actor_id, user, doc):
        return doc["owner_id"] == actor_id or actor_id in doc["shared"] or user["role"] == "admin"

    def create(self, actor_id, title, body):
        self._actor(actor_id)
        doc = {"id": self._next, "owner_id": actor_id, "title": title, "body": body, "shared": {}}
        self._next += 1
        self._docs[doc["id"]] = doc
        return dict(doc)

    def get(self, actor_id, doc_id):
        user = self._actor(actor_id)
        doc = self._docs.get(doc_id)
        if doc is None or not self._visible(actor_id, user, doc):
            raise NotFound(doc_id)
        return dict(doc)

    def list(self, actor_id):
        user = self._actor(actor_id)
        return [dict(d) for d in sorted(self._docs.values(), key=lambda d: d["id"]) if self._visible(actor_id, user, d)]

    def update(self, actor_id, doc_id, changes):
        self.get(actor_id, doc_id)
        doc = self._docs[doc_id]
        doc.update(changes)
        return dict(doc)

    def share(self, actor_id, doc_id, target_id, level):
        self.get(actor_id, doc_id)
        doc = self._docs[doc_id]
        doc["shared"][target_id] = level
        return dict(doc)

    def delete(self, actor_id, doc_id):
        self.get(actor_id, doc_id)
        del self._docs[doc_id]
