# Python testing

Style rules for Python tests. Where tests live and which services exist are project facts; see `project.md`.

## Naming

Pattern: `test_<subject>_<condition>_<expected>`

```python
def test_create_order_duplicate_id_raises_conflict(): ...
def test_find_user_unknown_id_returns_none(): ...
```

## Scope

- pytest with plain `assert`; parametrize (`@pytest.mark.parametrize`) for table-style cases instead of loops.
- Unit tests touch no network, database or clock; fake collaborators through fixtures, `monkeypatch` or `unittest.mock`.
- Real infrastructure (database, broker) through containers in a separate integration location, not an in-memory
  substitute with different semantics.
- Assert behavior and the exact error (`pytest.raises(..., match=...)`), not only that something was raised.

## Isolation

- No shared mutable state between tests (module globals, ordering); each test builds its own data, fixtures are function-scoped by default.
- No `time.sleep`: use a fake clock or poll with a timeout.
- A test that needs a skip or xfail says why and links the task.
