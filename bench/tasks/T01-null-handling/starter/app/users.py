def display_name(user):
    """Name shown in the UI for a user record (a dict)."""
    profile = user.get("profile")
    full = profile.get("full_name")
    return full.strip() or user["username"]


def load_display_name(repo, user_id):
    """Look a user up in `repo` (repo.get(id) -> dict or None) and return their display name."""
    try:
        user = repo.get(user_id)
        return display_name(user)
    except Exception:
        return ""
