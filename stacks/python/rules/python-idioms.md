# Python idioms

Style rules for Python code. Project-specific choices (framework, layout, Python version) are in `project.md`.

## Types and structure

- Type-annotate public functions and methods; keep `mypy` (or the project's checker) green on changed files.
- Prefer small functions and plain data (`dataclass`, `TypedDict`, Pydantic models at boundaries) over dicts passed around.
- Imports at the top of the module, absolute, no wildcard imports; no import-time side effects (network, file, env reads).

## Errors and resources

- Raise specific exceptions; never bare `except:` and never `except Exception: pass`. Re-raise with `raise ... from err`.
- `with` for files, locks, connections; no manual `close()` in the happy path only.
- No mutable default arguments; no `assert` for input validation (it is stripped under `-O`).

## Logging and secrets

- `logging` with lazy formatting, never `print` in library code; do not log secrets or full request bodies.
- Configuration through the environment or a settings object, never literals in code.
- TODOs carry a reference: `TODO(TASK-123)`.
