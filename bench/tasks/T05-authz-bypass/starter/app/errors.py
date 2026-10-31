class Unauthenticated(Exception):
    """The acting user is unknown or deactivated."""


class NotFound(Exception):
    """The document does not exist, or the actor may not know that it exists."""


class Forbidden(Exception):
    """The actor can see the document but may not perform this action."""
