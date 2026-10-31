class ItemStore:
    """In-memory item catalogue. Items are dicts with an integer 'id'. Insertion order is NOT id order."""

    def __init__(self, items=()):
        self._items = list(items)

    def all(self):
        return list(self._items)
