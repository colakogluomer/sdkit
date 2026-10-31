def _text(value):
    return value.strip() if isinstance(value, str) else ""


def display_name(user):
    if not isinstance(user, dict):
        return "Unknown user"
    profile = user.get("profile")
    full = _text(profile.get("full_name")) if isinstance(profile, dict) else ""
    return full or _text(user.get("username")) or "Unknown user"


def load_display_name(repo, user_id):
    try:
        user = repo.get(user_id)
        return display_name(user)
    except Exception:
        return ""
