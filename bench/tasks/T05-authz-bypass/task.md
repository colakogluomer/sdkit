# Close the authorization holes in `app/docs.py`

`DocService` only checks that the caller exists. Any user can read, list, edit, share and delete anyone's documents, and the caller can
rewrite fields they must never control. Enforce the rules below. Only `app/` may be changed; `tests/` is the visible example suite.
Users come from the trusted `directory` handed to the constructor; never trust anything the caller passes about themselves.
Returned documents are copies: mutating a returned dict (including its `shared` map) must never change stored state.

Identity
1. Every operation first requires the actor to exist in the directory AND be `active`. Otherwise raise `Unauthenticated`.
   This check comes before anything else, so it also hides whether a document exists.

Visibility
2. A document is visible to its owner, to any user it is shared with (`"read"` or `"write"`), and to users whose directory role is `"admin"`.
3. `get` of a document the actor cannot see raises `NotFound`, exactly like a missing id. `list` returns only visible documents ordered by id.

Writes
4. `update` is allowed for the owner and for users shared with `"write"`. A user who can see the document but only has `"read"`
   (or is an admin who is neither owner nor write-shared) gets `Forbidden`. Invisible documents raise `NotFound` (before any other check).
5. `update` may only change `title` and `body`. Any other key in `changes` (`owner_id`, `id`, `shared`, anything else) raises `ValueError`
   and the document is left completely unchanged (no partial application, even for the allowed keys in the same call).
6. `share` is allowed for the owner only. Other visible actors get `Forbidden`, invisible ones `NotFound`. `level` must be `"read"` or `"write"`,
   otherwise `ValueError`. The target must be an existing, active directory user, otherwise `ValueError`. Sharing again replaces the level
   (so write can be downgraded to read). The owner cannot be added to `shared`.
7. `delete` is allowed for the owner and for admins. Everyone else who can see the document gets `Forbidden`, invisible ones `NotFound`.
8. Rule order for every action on a document: Unauthenticated, then NotFound (invisible/missing), then Forbidden, then ValueError for bad input.
