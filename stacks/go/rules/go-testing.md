# Go testing

Style rules for Go tests. Where tests live and which sentinel errors exist are project facts; see `project.md`
("Test layout") and the project's own rules.

## Naming

Pattern: `TestSubject_Condition_ExpectedResult`

```go
func TestLoadOrder_NotFound_ReturnsNotFound(t *testing.T)
func TestCreateOrder_Duplicate_ReturnsConflict(t *testing.T)
```

- Subject is the function or method under test, condition is the input state, expected result is what is asserted.

## Stubs

Stubs implement an interface with in-memory state and live in `_test.go` files, never in production code.

- A stub implements the whole interface.
- Use a constructor `newStubX()` with sensible defaults.
- A stub may expose controllable failure fields (`fetchErr error`, `failAfter int`).
- Each test builds its own stub; tests never share mutable state or depend on order.

## What to test

Test behaviour, not the internal call sequence.

Priority:
1. Error paths (not found, conflict, forbidden, and the project's other sentinels)
2. Validation failures
3. Happy path
4. Edge cases (empty lists, zero values, boundaries)

## Assertions

Compare errors with `errors.Is`, never with string comparison:

```go
if !errors.Is(err, ErrNotFound) {
    t.Fatalf("expected ErrNotFound, got %v", err)
}
```

For "no error expected": `if err != nil { t.Fatalf("unexpected error: %v", err) }`.

## Table-driven tests

Use them when the same logic runs over several inputs and outputs. Use flat per-function tests when scenarios need
distinct setup or stub behaviour.

## Isolation

- Unit tests make no real network or database calls and use `context.Background()`.
- Integration tests against real infrastructure live where `project.md` says, and run only when the task asks for them.

## Coverage

Cover every error branch a service method returns and every validation rejection. Aim for meaningful scenario
coverage, not 100% of lines.
