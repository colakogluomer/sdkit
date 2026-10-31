import copy

from .errors import Forbidden, NotFound, Unauthenticated

_EDITABLE = ("title", "body")
_LEVELS = ("read", "write")


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
        try:
            user = self._directory.get(actor_id)
        except TypeError:
            user = None
        if not isinstance(user, dict) or user.get("active") is not True:
            raise Unauthenticated(actor_id)
        return user

    @staticmethod
    def _copy(doc):
        return copy.deepcopy(doc)

    def _visible(self, actor_id, user, doc):
        return doc["owner_id"] == actor_id or actor_id in doc["shared"] or user.get("role") == "admin"

    def _find(self, actor_id, doc_id):
        user = self._actor(actor_id)
        doc = self._docs.get(doc_id)
        if doc is None or not self._visible(actor_id, user, doc):
            raise NotFound(doc_id)
        return user, doc

    def create(self, actor_id, title, body):
        self._actor(actor_id)
        doc = {"id": self._next, "owner_id": actor_id, "title": title, "body": body, "shared": {}}
        self._next += 1
        self._docs[doc["id"]] = doc
        return self._copy(doc)

    def get(self, actor_id, doc_id):
        _, doc = self._find(actor_id, doc_id)
        return self._copy(doc)

    def list(self, actor_id):
        user = self._actor(actor_id)
        return [self._copy(d) for d in sorted(self._docs.values(), key=lambda d: d["id"])
                if self._visible(actor_id, user, d)]

    def update(self, actor_id, doc_id, changes):
        _, doc = self._find(actor_id, doc_id)
        if doc["owner_id"] != actor_id and doc["shared"].get(actor_id) != "write":
            raise Forbidden(doc_id)
        if not isinstance(changes, dict) or any(key not in _EDITABLE for key in changes):
            raise ValueError("only title and body can be changed")
        doc.update(changes)
        return self._copy(doc)

    def share(self, actor_id, doc_id, target_id, level):
        _, doc = self._find(actor_id, doc_id)
        if doc["owner_id"] != actor_id:
            raise Forbidden(doc_id)
        if level not in _LEVELS or not isinstance(level, str):
            raise ValueError("level must be read or write")
        target = self._directory.get(target_id) if isinstance(target_id, (int, str)) else None
        if not isinstance(target, dict) or target.get("active") is not True or target_id == doc["owner_id"]:
            raise ValueError("invalid share target")
        doc["shared"][target_id] = level
        return self._copy(doc)

    def delete(self, actor_id, doc_id):
        user, doc = self._find(actor_id, doc_id)
        if doc["owner_id"] != actor_id and user.get("role") != "admin":
            raise Forbidden(doc_id)
        del self._docs[doc_id]
