from .errors import ServiceError, UserNotFound


def _text(value):
    return value.strip() if isinstance(value, str) else ""


def display_name(user):
    """Name shown in the UI for a user record (a dict)."""
    if not isinstance(user, dict):
        return "Unknown user"
    profile = user.get("profile")
    full = _text(profile.get("full_name")) if isinstance(profile, dict) else ""
    return full or _text(user.get("username")) or "Unknown user"


def load_display_name(repo, user_id):
    """Look a user up in `repo` (repo.get(id) -> dict or None) and return their display name."""
    if user_id is None:
        raise ValueError("user_id is required")
    try:
        user = repo.get(user_id)
    except UserNotFound:
        raise
    except Exception as exc:
        raise ServiceError("user lookup failed") from exc
    if user is None:
        raise UserNotFound(user_id)
    return display_name(user)
