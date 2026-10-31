# Go idioms

Language-level rules that hold for any Go repo. Project architecture (layering, persistence, logging package, error
sentinels) belongs in the project's own rules, not here.

## Naming (Effective Go)

| Type              | Convention                             | Example                         |
|-------------------|----------------------------------------|---------------------------------|
| Packages          | lowercase, single word, no underscores | `orders`, `billing`, `resp`     |
| Exported types    | MixedCaps                              | `OrderRepository`               |
| Unexported types  | mixedCaps                              | `orderEntity`, `stubOrderRepo`  |
| Acronyms          | all caps or all lower per position     | `userID`, `httpClient`, `URL`   |
| Interfaces        | noun or -er suffix                     | `OrderRepository`, `Logger`     |
| Constructors      | `New<Type>`                            | `NewOrderRepository`            |

- Never name variables `data` or `result` generically; use the domain noun (`order`, `items`).
- Receivers: one lowercase letter matching the type (`h` for Handler, `r` for Repository, `s` for Service).

## Interfaces

- Define interfaces in the consuming package. Keep them small.
- Accept interfaces, return concrete types. A constructor returns the concrete type unless the project's rules say it
  returns a domain interface.
- A possibly-nil concrete pointer must never be assigned to an interface-typed field or parameter without a nil check:
  the result is a non-nil interface and `== nil` guards stop working.

## Errors

- Errors are values: always check them. Never discard one with `_` unless it is provably safe.
- Compare with `errors.Is` / `errors.As`, never by string.
- Wrap with context when crossing a layer: `fmt.Errorf("createOrder: %w", err)`.
- Return `(T, error)` from every fallible function. No `panic` in production code.

## Context

- `ctx context.Context` is always the first parameter. Pass it to every database and network call.
- Never store a context in a struct.
- Give long-running calls their own bounded sub-context; a call without one can hold a pooled connection after the
  request is cancelled.

## Structs and zero values

- Design structs so the zero value is valid or safe; fail fast in constructors.
- Use pointer fields only when `nil` carries meaning (optional or absent value).
- Preallocate with `make([]T, 0, n)` or `make([]T, n)` when the length is known.

## Defer

- `defer` cleanup immediately after acquiring the resource.
- Check the error from a deferred `Close()` on any non-trivial path.
- Do not `defer` inside hot loops.

## Goroutines

- Do not introduce goroutines unless the task requires them. Prefer sequential code.
- If used, document ownership and lifecycle and always provide a way to stop them.

## Do not

- Use `init()` functions.
- Shadow `err` in inner blocks without a strong reason.
- Print with `fmt.Println` / `log.Printf` in production code; use the project's logger.
