# Fix null handling and error propagation in `app/users.py`

`display_name(user)` and `load_display_name(repo, user_id)` crash on incomplete records and hide real failures.
Fix them so that all of the following hold. Only `app/` may be changed; `tests/` is the visible example suite.

1. `display_name` returns `profile.full_name` stripped, when it is a non-blank string.
2. Otherwise (profile missing or `None`, `full_name` missing, `None`, not a string, or blank) it returns the stripped `username`.
3. If there is no usable username either, or `user` is `None`, it returns `"Unknown user"`. It never raises for dict or `None` input.
4. `load_display_name` raises `ValueError` when `user_id` is `None`, without calling the repository.
5. A missing user (`repo.get` returns `None`) raises `UserNotFound`.
6. Any other exception raised by the repository is re-raised as `ServiceError` with the original as `__cause__`. It is never swallowed and never turned into an empty string.
7. `UserNotFound` raised by the repository itself passes through unchanged (not wrapped).
8. A successful lookup still returns the display name from rules 1 to 3.
